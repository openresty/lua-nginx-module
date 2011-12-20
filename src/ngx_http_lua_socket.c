#ifndef DDEBUG
#define DDEBUG 0
#endif
#include "ddebug.h"

#include "ngx_http_lua_socket.h"
#include "ngx_http_lua_contentby.h"


#define NGX_HTTP_LUA_SOCKET_FT_ERROR        0x0001
#define NGX_HTTP_LUA_SOCKET_FT_TIMEOUT      0x0002
#define NGX_HTTP_LUA_SOCKET_FT_CLOSED       0x0004


static int ngx_http_lua_socket_tcp(lua_State *L);
static int ngx_http_lua_socket_tcp_connect(lua_State *L);
static int ngx_http_lua_socket_tcp_receive(lua_State *L);
static int ngx_http_lua_socket_tcp_send(lua_State *L);
static int ngx_http_lua_socket_tcp_close(lua_State *L);
static int ngx_http_lua_socket_tcp_setoption(lua_State *L);
static int ngx_http_lua_socket_tcp_settimeout(lua_State *L);
static void ngx_http_lua_socket_tcp_handler(ngx_event_t *ev);
static ngx_int_t ngx_http_lua_socket_tcp_get_peer(ngx_peer_connection_t *pc,
    void *data);
static void ngx_http_lua_socket_read_handler(ngx_http_request_t *r,
    ngx_http_lua_socket_upstream_t *u);
static void ngx_http_lua_socket_send_handler(ngx_http_request_t *r,
    ngx_http_lua_socket_upstream_t *u);
static void ngx_http_lua_socket_connected_handler(ngx_http_request_t *r,
    ngx_http_lua_socket_upstream_t *u);
static void ngx_http_lua_socket_cleanup(void *data);
static void ngx_http_lua_socket_finalize(ngx_http_request_t *r,
    ngx_http_lua_socket_upstream_t *u);
static ngx_int_t ngx_http_lua_socket_send(ngx_http_request_t *r,
    ngx_http_lua_socket_upstream_t *u);
static ngx_int_t ngx_http_lua_socket_test_connect(ngx_connection_t *c);
static void ngx_http_lua_socket_handle_error(ngx_http_request_t *r,
    ngx_http_lua_socket_upstream_t *u, ngx_uint_t ft_type);
static void ngx_http_lua_socket_handle_success(ngx_http_request_t *r,
    ngx_http_lua_socket_upstream_t *u);
static int ngx_http_lua_socket_tcp_send_retval_handler(ngx_http_request_t *r,
    ngx_http_lua_socket_upstream_t *u, lua_State *L);
static int ngx_http_lua_socket_tcp_connect_retval_handler(ngx_http_request_t *r,
    ngx_http_lua_socket_upstream_t *u, lua_State *L);
static void ngx_http_lua_socket_dummy_handler(ngx_http_request_t *r,
    ngx_http_lua_socket_upstream_t *u);
static ngx_int_t ngx_http_lua_socket_read(ngx_http_request_t *r,
    ngx_http_lua_socket_upstream_t *u);
static void ngx_http_lua_socket_read_handler(ngx_http_request_t *r,
    ngx_http_lua_socket_upstream_t *u);
static int ngx_http_lua_socket_tcp_receive_retval_handler(ngx_http_request_t *r,
    ngx_http_lua_socket_upstream_t *u, lua_State *L);
static ngx_int_t ngx_http_lua_socket_read_line(void *data, ssize_t bytes);


void
ngx_http_lua_inject_socket_api(lua_State *L)
{
    lua_createtable(L, 0, 4 /* nrec */);    /* ngx.socket */
    lua_pushcfunction(L, ngx_http_lua_socket_tcp);
    lua_setfield(L, -2, "tcp");

    /* {{{tcp object metatable */

    lua_createtable(L, 0 /* narr */, 7 /* nrec */);

    lua_pushcfunction(L, ngx_http_lua_socket_tcp_connect);
    lua_setfield(L, -2, "connect");

    lua_pushcfunction(L, ngx_http_lua_socket_tcp_receive);
    lua_setfield(L, -2, "receive");

    lua_pushcfunction(L, ngx_http_lua_socket_tcp_send);
    lua_setfield(L, -2, "send");

    lua_pushcfunction(L, ngx_http_lua_socket_tcp_close);
    lua_setfield(L, -2, "close");

    lua_pushcfunction(L, ngx_http_lua_socket_tcp_setoption);
    lua_setfield(L, -2, "setoption");

    lua_pushcfunction(L, ngx_http_lua_socket_tcp_settimeout);
    lua_setfield(L, -2, "settimeout"); /* ngx socket mt */

    lua_pushvalue(L, -1);
    lua_setfield(L, -2, "__index");
    lua_setfield(L, -3, "_tcp_meta");

    /* }}} */

    lua_setfield(L, -2, "socket");
}


static int
ngx_http_lua_socket_tcp(lua_State *L)
{
    if (lua_gettop(L) != 0) {
        return luaL_error(L, "expecting zero arguments, but got %d",
                lua_gettop(L));
    }

    lua_createtable(L, 0 /* narr */, 4 /* nrec */);
    lua_getglobal(L, "ngx");
    lua_getfield(L, -1, "_tcp_meta");

    dd("meta table: %s", luaL_typename(L, -1));
    lua_getfield(L, -1, "connect");
    dd("connect method: %s", luaL_typename(L, -1));
    lua_pop(L, 1);

    lua_setmetatable(L, -3);
    lua_pop(L, 1);

    dd("top: %d", lua_gettop(L));

    return 1;
}


static int
ngx_http_lua_socket_tcp_connect(lua_State *L)
{
    ngx_http_request_t          *r;
    ngx_http_lua_ctx_t          *ctx;
    ngx_int_t                    rc;
    ngx_peer_connection_t       *pc;
    ngx_connection_t            *c;
    ngx_url_t                    url;
    ngx_http_cleanup_t          *cln;
    ngx_http_lua_loc_conf_t     *llcf;

    ngx_http_lua_socket_upstream_t          *u;

    if (lua_gettop(L) != 3) {
        return luaL_error(L, "ngx.socket connect: expecting 2 argument but "
                "seen %d", lua_gettop(L));
    }

    lua_getglobal(L, GLOBALS_SYMBOL_REQUEST);
    r = lua_touserdata(L, -1);
    lua_pop(L, 1);

    ngx_memzero(&url, sizeof(ngx_url_t));

    url.url.data = (u_char *) luaL_checklstring(L, 2, &url.url.len);
    url.default_port = luaL_checkinteger(L, 3);
    /* TODO: u.no_resolve = 1; */

    if (ngx_parse_url(r->pool, &url) != NGX_OK) {

        if (url.err) {
            lua_pushnil(L);
            lua_pushfstring(L, "bad server name: %s", url.err);
            return 2;
        }

        lua_pushnil(L);
        lua_pushliteral(L, "bad server name: %s");
        return 2;
    }

    if (!url.addrs || !url.addrs[0].sockaddr) {
        lua_pushnil(L);
        lua_pushliteral(L, "DNS resolver not supported yet");
        return 2;
    }

    r->connection->log->action = "connecting to upstream via lua tcp socket";

    r->connection->single_connection = 0;

    /* TODO we should not allocate the peer connection in the nginx pool */

    u = ngx_pcalloc(r->pool, sizeof(ngx_http_lua_socket_upstream_t));
    if (u == NULL) {
        return luaL_error(L, "out of memory");
    }

    u->request = r; /* set the controlling request */

    llcf = ngx_http_get_module_loc_conf(r, ngx_http_lua_module);

    u->conf = llcf;

    pc = &u->peer;

    pc->log = r->connection->log;
    pc->log_error = NGX_ERROR_ERR;

    pc->sockaddr = url.addrs[0].sockaddr;
    pc->socklen = url.addrs[0].socklen;
    pc->name = &url.host;

    pc->get = ngx_http_lua_socket_tcp_get_peer;

    rc = ngx_event_connect_peer(pc);

    ngx_log_debug1(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                   "lua tcp socket connect: %i", rc);

    if (rc == NGX_ERROR) {
        lua_pushnil(L);
        lua_pushliteral(L, "connect peer error");
        return 2;
    }

    if (rc == NGX_BUSY) {
        lua_pushnil(L);
        lua_pushliteral(L, "no live connection");
        return 2;
    }

    if (rc == NGX_DECLINED) {
        lua_pushnil(L);
        lua_pushliteral(L, "no peer found");
        return 2;
    }

    /* rc == NGX_OK || rc == NGX_AGAIN */

    lua_pushlightuserdata(L, u);
    lua_setfield(L, 1, "_ud");

    cln = ngx_http_cleanup_add(r, 0);
    if (cln == NULL) {
        return luaL_error(L, "out of memory");
    }

    cln->handler = ngx_http_lua_socket_cleanup;
    cln->data = u;
    u->cleanup = &cln->handler;

    c = pc->connection;

    c->data = u;

    c->write->handler = ngx_http_lua_socket_tcp_handler;
    c->read->handler = ngx_http_lua_socket_tcp_handler;

    u->write_event_handler = ngx_http_lua_socket_connected_handler;
    u->read_event_handler = ngx_http_lua_socket_connected_handler;

    c->sendfile &= r->connection->sendfile;
    u->output.sendfile = c->sendfile;

    c->pool = r->pool;
    c->log = r->connection->log;
    c->read->log = c->log;
    c->write->log = c->log;

    /* init or reinit the ngx_output_chain() and ngx_chain_writer() contexts */

    u->writer.out = NULL;
    u->writer.last = &u->writer.out;
    u->writer.connection = c;
    u->writer.limit = 0;
    u->request_sent = 0;

    ctx = ngx_http_get_module_ctx(r, ngx_http_lua_module);

    if (rc == NGX_OK) {
        lua_pushinteger(L, 1);
        lua_pushnil(L);
        return 2;
    }

    /* rc == NGX_AGAIN */

    /* TODO we should also support socket:settimeout() here */
    ngx_add_timer(c->write, llcf->connect_timeout);

    if (ctx->entered_content_phase) {
        r->write_event_handler = ngx_http_lua_content_wev_handler;
    }

    u->waiting = 1;

    ctx->data = u;
    u->prepare_retvals = ngx_http_lua_socket_tcp_connect_retval_handler;

    ctx->socket_busy = 1;
    ctx->socket_ready = 0;

    return lua_yield(L, 0);
}


static int
ngx_http_lua_socket_error_retval_handler(ngx_http_request_t *r,
    ngx_http_lua_socket_upstream_t *u, lua_State *L)
{
    lua_pushnil(L);

    switch (u->ft_type) {
    case NGX_HTTP_LUA_SOCKET_FT_TIMEOUT:
        lua_pushliteral(L, "timeout");
        break;

    case NGX_HTTP_LUA_SOCKET_FT_CLOSED:
        lua_pushliteral(L, "closed");
        break;

    default:
        lua_pushliteral(L, "error");
        break;
    }

    return 2;
}


static int
ngx_http_lua_socket_tcp_connect_retval_handler(ngx_http_request_t *r,
    ngx_http_lua_socket_upstream_t *u, lua_State *L)
{
    if (u->ft_type) {
        return ngx_http_lua_socket_error_retval_handler(r, u, L);
    }

    lua_pushinteger(L, 1);
    lua_pushnil(L);
    return 2;
}


static int
ngx_http_lua_socket_tcp_receive(lua_State *L)
{
    ngx_http_request_t                  *r;
    ngx_http_lua_socket_upstream_t      *u;
    ngx_int_t                            rc;
    ngx_http_lua_ctx_t                  *ctx;

    /* TODO: support the pattern argument */

    if (lua_gettop(L) != 1) {
        return luaL_error(L, "expecting one arguments (one for the object), "
                          "but got %d", lua_gettop(L));
    }

    dd("sock:receive");

    lua_getglobal(L, GLOBALS_SYMBOL_REQUEST);
    r = lua_touserdata(L, -1);
    lua_pop(L, 1);

    luaL_checktype(L, 1, LUA_TTABLE);

    lua_getfield(L, 1, "_ud");
    u = lua_touserdata(L, -1);
    if (u == NULL) {
        lua_pushnil(L);
        lua_pushliteral(L, "not connected");
        return 2;
    }

    if (u->buffer.start == NULL) {
        u->buffer.start = ngx_palloc(r->pool, u->conf->buffer_size);
        if (u->buffer.start == NULL) {
            return luaL_error(L, "out of memory");
        }

        u->buffer.pos = u->buffer.start;
        u->buffer.last = u->buffer.start;
        u->buffer.end = u->buffer.start + u->conf->buffer_size;
        u->buffer.temporary = 1;
        u->buffer.tag = u->output.tag;
    }

    u->luabuf_inited = 0;
    u->input_filter = ngx_http_lua_socket_read_line;
    u->input_filter_ctx = u;

    rc = ngx_http_lua_socket_read(r, u);

    if (rc == NGX_ERROR) {
        return ngx_http_lua_socket_error_retval_handler(r, u, L);
    }

    if (rc == NGX_OK) {
        if (u->luabuf_inited) {
            dd("push the luabuf result");
            luaL_pushresult(&u->luabuf);
            u->luabuf_inited = 0;

        } else {
            dd("push nil result");
            lua_pushnil(L);
        }

        lua_pushnil(L);
        return 2;
    }

    /* rc == NGX_AGAIN */

    ctx = ngx_http_get_module_ctx(r, ngx_http_lua_module);

    u->read_event_handler = ngx_http_lua_socket_read_handler;
    u->waiting = 1;

    ctx->data = u;
    u->prepare_retvals = ngx_http_lua_socket_tcp_receive_retval_handler;

    ctx->socket_busy = 1;
    ctx->socket_ready = 0;

    return lua_yield(L, 0);
}


static ngx_int_t
ngx_http_lua_socket_read_line(void *data, ssize_t bytes)
{
    ngx_http_lua_socket_upstream_t      *u = data;

    ngx_buf_t                   *b;
    u_char                      *pos;
    u_char                      *last;
    ngx_http_lua_ctx_t          *ctx;
    ngx_http_request_t          *r;

    if (!u->luabuf_inited) {
        r = u->request;
        ctx = ngx_http_get_module_ctx(r, ngx_http_lua_module);
        luaL_buffinit(ctx->cc, &u->luabuf);
        u->luabuf_inited = 1;
    }

    b = &u->buffer;
    pos = b->pos;

    while (bytes--) {
        if (*b->pos++ == '\n') {
            last = b->pos - 2;
            if (last >= pos && *last == '\r') {
                /* do nothing */

            } else {
                last++;
            }

            luaL_addlstring(&u->luabuf, (char *) pos, last - pos);
            return NGX_OK;
        }
    }

    luaL_addlstring(&u->luabuf, (char *) pos, b->pos - pos);

    return NGX_AGAIN;
}


static ngx_int_t
ngx_http_lua_socket_read(ngx_http_request_t *r,
    ngx_http_lua_socket_upstream_t *u)
{
    ngx_int_t                    rc;
    ngx_connection_t            *c;
    ngx_buf_t                   *b;
    ngx_event_t                 *rev;
    size_t                       size;
    ssize_t                      n;
    unsigned                     read;

    c = u->peer.connection;
    rev = c->read;

    ngx_log_debug0(NGX_LOG_DEBUG_HTTP, c->log, 0,
                   "lua socket read data");

    b = &u->buffer;
    read = 0;

    for ( ;; ) {

        size = b->last - b->pos;
        if (size) {
            rc = u->input_filter(u->input_filter_ctx, size);
            if (rc == NGX_OK) {
                dd("lua socket read done");
                u->write_event_handler = ngx_http_lua_socket_dummy_handler;
                ngx_http_lua_socket_handle_success(r, u);
                break;
            }

            if (rc == NGX_ERROR) {
                ngx_http_lua_socket_handle_error(r, u,
                                                 NGX_HTTP_LUA_SOCKET_FT_ERROR);
                return NGX_ERROR;
            }

            /* rc == NGX_AGAIN */
            continue;
        }

        if (read && !rev->ready) {
            rc = NGX_AGAIN;
            break;
        }

        /* try to read the socket */

        size = b->end - b->last;

        if (size == 0) {
            /* TODO: flush the buffer onto luaL_Buffer */
            ngx_http_lua_socket_handle_error(r, u,
                                             NGX_HTTP_LUA_SOCKET_FT_ERROR);
            return NGX_ERROR;
        }

        n = c->recv(c, b->last, size);
        read = 1;

        if (n == NGX_AGAIN) {
            rc = NGX_AGAIN;
            dd("socket recv busy");
            break;
        }

        if (n == 0) {
            ngx_http_lua_socket_handle_error(r, u,
                                             NGX_HTTP_LUA_SOCKET_FT_CLOSED);
            return NGX_ERROR;
        }

        if (n == NGX_ERROR) {
            ngx_http_lua_socket_handle_error(r, u,
                                             NGX_HTTP_LUA_SOCKET_FT_ERROR);
            return NGX_ERROR;
        }

        b->last += n;
    }

    if (ngx_handle_read_event(rev, 0) != NGX_OK) {
        ngx_http_lua_socket_handle_error(r, u, NGX_HTTP_LUA_SOCKET_FT_ERROR);
        return NGX_ERROR;
    }

    if (rev->active) {
        ngx_add_timer(rev, u->conf->read_timeout);

    } else if (rev->timer_set) {
        ngx_del_timer(rev);
    }

    return rc;
}


static int
ngx_http_lua_socket_tcp_send(lua_State *L)
{
    ngx_int_t                            rc;
    ngx_http_request_t                  *r;
    u_char                              *p;
    size_t                               len;
    ngx_http_core_loc_conf_t            *clcf;
    ngx_chain_t                         *cl;
    ngx_http_lua_ctx_t                  *ctx;
    ngx_http_lua_socket_upstream_t      *u;

    /* TODO: add support for the optional "i" and "j" arguments */

    if (lua_gettop(L) != 2) {
        return luaL_error(L, "expecting two arguments (one for the object), "
                          "but got %d", lua_gettop(L));
    }

    lua_getglobal(L, GLOBALS_SYMBOL_REQUEST);
    r = lua_touserdata(L, -1);
    lua_pop(L, 1);

    luaL_checktype(L, 1, LUA_TTABLE);

    lua_getfield(L, 1, "_ud");
    u = lua_touserdata(L, -1);
    if (u == NULL) {
        lua_pushnil(L);
        lua_pushliteral(L, "not connected");
        return 2;
    }

    p = (u_char *) luaL_checklstring(L, 2, &len);

    cl = ngx_chain_get_free_buf(r->pool, &u->free_bufs);
    if (cl == NULL) {
        return luaL_error(L, "out of memory");
    }

    cl->buf->temporary = 1;
    cl->buf->memory = 0;

    cl->buf->start = ngx_palloc(r->pool, len);
    if (cl->buf->start == NULL) {
        return luaL_error(L, "out of memory");
    }

    cl->buf->end = cl->buf->start + len;
    cl->buf->pos = cl->buf->start;
    cl->buf->last = ngx_copy(cl->buf->pos, p, len);

    u->request_bufs = cl;

    u->request_len = len;
    u->request_sent = 0;
    u->ft_type = 0;

    /* mimic ngx_http_upstream_init_request here */

    if (u->output.pool == NULL) {
        clcf = ngx_http_get_module_loc_conf(r, ngx_http_core_module);

        u->output.alignment = clcf->directio_alignment;
        u->output.pool = r->pool;
        u->output.bufs.num = 1;
        u->output.bufs.size = clcf->client_body_buffer_size;
        u->output.output_filter = ngx_chain_writer;
        u->output.filter_ctx = &u->writer;
        u->output.tag = (ngx_buf_tag_t) &ngx_http_lua_module;

        u->writer.pool = r->pool;
    }

    rc = ngx_http_lua_socket_send(r, u);

    if (rc == NGX_ERROR) {
        return ngx_http_lua_socket_error_retval_handler(r, u, L);
    }

    if (rc == NGX_OK) {
        lua_pushinteger(L, len);
        lua_pushnil(L);
        return 2;
    }

    /* rc == NGX_AGAIN */

    ctx = ngx_http_get_module_ctx(r, ngx_http_lua_module);

    u->waiting = 1;

    ctx->data = u;
    u->prepare_retvals = ngx_http_lua_socket_tcp_send_retval_handler;

    ctx->socket_busy = 0;
    ctx->socket_ready = 1;

    return lua_yield(L, 0);
}


static int
ngx_http_lua_socket_tcp_send_retval_handler(ngx_http_request_t *r,
    ngx_http_lua_socket_upstream_t *u, lua_State *L)
{
    if (u->ft_type) {
        return ngx_http_lua_socket_error_retval_handler(r, u, L);
    }

    lua_pushinteger(L, u->request_len);
    lua_pushnil(L);
    return 2;
}


static int
ngx_http_lua_socket_tcp_receive_retval_handler(ngx_http_request_t *r,
    ngx_http_lua_socket_upstream_t *u, lua_State *L)
{
    if (u->ft_type) {
        return ngx_http_lua_socket_error_retval_handler(r, u, L);
    }

    if (u->luabuf_inited) {
        dd("push the luabuf result");
        luaL_pushresult(&u->luabuf);
        u->luabuf_inited = 0;

    } else {
        dd("push nil result");
        lua_pushnil(L);
    }

    lua_pushnil(L);
    return 2;
}


static int
ngx_http_lua_socket_tcp_close(lua_State *L)
{
    /* TODO */
    return 0;
}


static int
ngx_http_lua_socket_tcp_setoption(lua_State *L)
{
    /* TODO */
    return 0;
}


static int
ngx_http_lua_socket_tcp_settimeout(lua_State *L)
{
    /* TODO */
    return 0;
}


static void
ngx_http_lua_socket_tcp_handler(ngx_event_t *ev)
{
    ngx_connection_t                *c;
    ngx_http_request_t              *r;
    ngx_http_log_ctx_t              *ctx;
    ngx_http_lua_socket_upstream_t  *u;

    c = ev->data;
    u = c->data;
    r = u->request;
    c = r->connection;

    ctx = c->log->data;
    ctx->current_request = r;

    ngx_log_debug2(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                   "lua socket request: \"%V?%V\"", &r->uri, &r->args);

    if (ev->write) {
        u->write_event_handler(r, u);

    } else {
        u->read_event_handler(r, u);
    }

    ngx_http_run_posted_requests(c);
}


static ngx_int_t
ngx_http_lua_socket_tcp_get_peer(ngx_peer_connection_t *pc, void *data)
{
    /* empty */
    return NGX_OK;
}


static void
ngx_http_lua_socket_read_handler(ngx_http_request_t *r,
    ngx_http_lua_socket_upstream_t *u)
{
    ngx_connection_t            *c;

    c = u->peer.connection;

    ngx_log_debug0(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                   "lua socket read handler");

    if (c->read->timedout) {
        ngx_http_lua_socket_handle_error(r, u, NGX_HTTP_LUA_SOCKET_FT_TIMEOUT);
        return;
    }

    if (u->buffer.start != NULL) {
        (void) ngx_http_lua_socket_read(r, u);
    }
}


static void
ngx_http_lua_socket_send_handler(ngx_http_request_t *r,
    ngx_http_lua_socket_upstream_t *u)
{
    ngx_connection_t            *c;

    c = u->peer.connection;

    ngx_log_debug0(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                   "lua socket send handler");

    if (c->write->timedout) {
        ngx_http_lua_socket_handle_error(r, u, NGX_HTTP_LUA_SOCKET_FT_TIMEOUT);
        return;
    }

    if (u->request_bufs) {
        (void) ngx_http_lua_socket_send(r, u);
    }
}


static ngx_int_t
ngx_http_lua_socket_send(ngx_http_request_t *r,
    ngx_http_lua_socket_upstream_t *u)
{
    ngx_int_t                    rc;
    ngx_connection_t            *c;

    c = u->peer.connection;

    ngx_log_debug0(NGX_LOG_DEBUG_HTTP, c->log, 0,
                   "lua socket send data");

    if (!u->request_sent && ngx_http_lua_socket_test_connect(c) != NGX_OK) {
        ngx_http_lua_socket_handle_error(r, u, NGX_HTTP_LUA_SOCKET_FT_ERROR);
        return NGX_ERROR;
    }

    c->log->action = "sending data to upstream";

    rc = ngx_output_chain(&u->output, u->request_sent ? NULL : u->request_bufs);

    u->request_sent = 1;

    if (rc == NGX_ERROR) {
        ngx_http_lua_socket_handle_error(r, u, NGX_HTTP_LUA_SOCKET_FT_ERROR);
        return NGX_ERROR;
    }

    if (c->write->timer_set) {
        ngx_del_timer(c->write);
    }

    if (rc == NGX_AGAIN) {
        u->write_event_handler = ngx_http_lua_socket_send_handler;

        ngx_add_timer(c->write, u->conf->send_timeout);

        if (ngx_handle_write_event(c->write, u->conf->send_lowat) != NGX_OK) {
            ngx_http_lua_socket_handle_error(r, u,
                                             NGX_HTTP_LUA_SOCKET_FT_ERROR);
            return NGX_ERROR;
        }

        return NGX_AGAIN;
    }

    /* rc == NGX_OK */

    u->request_bufs = NULL;
    u->request_sent = 0;
    u->write_event_handler = ngx_http_lua_socket_dummy_handler;

    if (ngx_handle_write_event(c->write, 0) != NGX_OK) {
        ngx_http_lua_socket_handle_error(r, u, NGX_HTTP_LUA_SOCKET_FT_ERROR);
        return NGX_ERROR;
    }

    ngx_http_lua_socket_handle_success(r, u);
    return NGX_OK;
}


static void
ngx_http_lua_socket_handle_success(ngx_http_request_t *r,
    ngx_http_lua_socket_upstream_t *u)
{
    ngx_http_lua_ctx_t          *ctx;

    if (u->waiting) {
        u->waiting = 0;

        ctx = ngx_http_get_module_ctx(r, ngx_http_lua_module);

        ctx->socket_busy = 0;
        ctx->socket_ready = 1;

        ngx_http_post_request(r, NULL);
    }
}


static void
ngx_http_lua_socket_handle_error(ngx_http_request_t *r,
    ngx_http_lua_socket_upstream_t *u, ngx_uint_t ft_type)
{
    ngx_http_lua_ctx_t          *ctx;

    u->ft_type |= ft_type;
    ngx_http_lua_socket_finalize(r, u);

    if (u->waiting) {
        u->waiting = 0;

        ctx = ngx_http_get_module_ctx(r, ngx_http_lua_module);

        ctx->socket_busy = 0;
        ctx->socket_ready = 1;

        ngx_http_post_request(r, NULL);
    }

    u->read_event_handler = ngx_http_lua_socket_dummy_handler;
    u->write_event_handler = ngx_http_lua_socket_dummy_handler;
}


static void
ngx_http_lua_socket_connected_handler(ngx_http_request_t *r,
    ngx_http_lua_socket_upstream_t *u)
{
    ngx_http_lua_ctx_t          *ctx;

    ctx = ngx_http_get_module_ctx(r, ngx_http_lua_module);

    ctx->socket_busy = 0;
    ctx->socket_ready = 1;

    /* TODO maybe we should delete the current write/read event
     * here because the socket object may not be used immediately
     * on the Lua land, thus causing hot spin around level triggered
     * event poll and wasting CPU cycles. */

    u->read_event_handler = ngx_http_lua_socket_dummy_handler;
    u->write_event_handler = ngx_http_lua_socket_dummy_handler;

    ngx_http_post_request(r, NULL);
}


static void
ngx_http_lua_socket_cleanup(void *data)
{
    ngx_http_lua_socket_upstream_t  *u = data;

    ngx_http_request_t  *r;

    r = u->request;

    ngx_log_debug1(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                   "cleanup lua socket upstream request: \"%V\"", &r->uri);

    ngx_http_lua_socket_finalize(r, u);
}


static void
ngx_http_lua_socket_finalize(ngx_http_request_t *r,
    ngx_http_lua_socket_upstream_t *u)
{
    ngx_log_debug0(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                   "finalize lua socket");

    if (u->cleanup) {
        *u->cleanup = NULL;
        u->cleanup = NULL;
    }

    if (u->peer.free) {
        u->peer.free(&u->peer, u->peer.data, 0);
    }

    if (u->peer.connection) {
        ngx_close_connection(u->peer.connection);
    }

    u->peer.connection = NULL;
}


static ngx_int_t
ngx_http_lua_socket_test_connect(ngx_connection_t *c)
{
    int        err;
    socklen_t  len;

#if (NGX_HAVE_KQUEUE)

    if (ngx_event_flags & NGX_USE_KQUEUE_EVENT)  {
        if (c->write->pending_eof) {
            c->log->action = "connecting to upstream";
            (void) ngx_connection_error(c, c->write->kq_errno,
                                    "kevent() reported that connect() failed");
            return NGX_ERROR;
        }

    } else
#endif
    {
        err = 0;
        len = sizeof(int);

        /*
         * BSDs and Linux return 0 and set a pending error in err
         * Solaris returns -1 and sets errno
         */

        if (getsockopt(c->fd, SOL_SOCKET, SO_ERROR, (void *) &err, &len)
            == -1)
        {
            err = ngx_errno;
        }

        if (err) {
            c->log->action = "connecting to upstream";
            (void) ngx_connection_error(c, err, "connect() failed");
            return NGX_ERROR;
        }
    }

    return NGX_OK;
}


static void
ngx_http_lua_socket_dummy_handler(ngx_http_request_t *r,
    ngx_http_lua_socket_upstream_t *u)
{
    ngx_log_debug0(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                   "lua socket dummy handler");
}

