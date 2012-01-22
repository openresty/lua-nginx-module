#ifndef DDEBUG
#define DDEBUG 0
#endif
#include "ddebug.h"

#include "ngx_http_lua_socket.h"
#include "ngx_http_lua_contentby.h"


#define NGX_HTTP_LUA_SOCKET_FT_ERROR        0x0001
#define NGX_HTTP_LUA_SOCKET_FT_TIMEOUT      0x0002
#define NGX_HTTP_LUA_SOCKET_FT_CLOSED       0x0004
#define NGX_HTTP_LUA_SOCKET_FT_RESOLVER     0x0008
#define NGX_HTTP_LUA_SOCKET_FT_BUFTOOSMALL  0x0010


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
static void ngx_http_lua_socket_resolve_handler(ngx_resolver_ctx_t *ctx);
static int ngx_http_lua_socket_resolve_retval_handler(ngx_http_request_t *r,
    ngx_http_lua_socket_upstream_t *u, lua_State *L);
static int ngx_http_lua_socket_error_retval_handler(ngx_http_request_t *r,
    ngx_http_lua_socket_upstream_t *u, lua_State *L);
static ngx_int_t ngx_http_lua_socket_read_all(void *data, ssize_t bytes);
static ngx_int_t ngx_http_lua_socket_read_until(void *data, ssize_t bytes);
static ngx_int_t ngx_http_lua_socket_read_chunk(void *data, ssize_t bytes);
static int ngx_http_lua_socket_tcp_receiveuntil(lua_State *L);
static int ngx_http_lua_socket_receiveuntil_iterator(lua_State *L);
static ngx_int_t ngx_http_lua_socket_compile_pattern(u_char *data, size_t len,
    ngx_http_lua_socket_compiled_pattern_t *cp, ngx_log_t *log);
static int ngx_http_lua_socket_cleanup_compiled_pattern(lua_State *L);


void
ngx_http_lua_inject_socket_api(ngx_log_t *log, lua_State *L)
{
    ngx_int_t         rc;

    lua_createtable(L, 0, 4 /* nrec */);    /* ngx.socket */
    lua_pushcfunction(L, ngx_http_lua_socket_tcp);
    lua_setfield(L, -2, "tcp");

    {
        const char    buf[] = "local sock = ngx.socket.tcp()"
                   " local ok, err = sock:connect(...)"
                   " if ok then return sock else return nil, err end";

        rc = luaL_loadbuffer(L, buf, sizeof(buf) - 1, "ngx.socket.connect");
    }

    if (rc != NGX_OK) {
        ngx_log_error(NGX_LOG_CRIT, log, 0,
                      "failed to load Lua code for ngx.socket.connect(): %i",
                      rc);

    } else {
        lua_setfield(L, -2, "connect");
    }

    /* {{{tcp object metatable */

    lua_createtable(L, 0 /* narr */, 7 /* nrec */);

    lua_pushcfunction(L, ngx_http_lua_socket_tcp_connect);
    lua_setfield(L, -2, "connect");

    lua_pushcfunction(L, ngx_http_lua_socket_tcp_receive);
    lua_setfield(L, -2, "receive");

    lua_pushcfunction(L, ngx_http_lua_socket_tcp_receiveuntil);
    lua_setfield(L, -2, "receiveuntil");

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
    ngx_str_t                    host;
    int                          port;
    ngx_resolver_ctx_t          *rctx, temp;
    ngx_http_core_loc_conf_t    *clcf;
    int                          saved_top;
    int                          n;
    u_char                      *p;
    size_t                       len;
    ngx_url_t                    url;
    ngx_int_t                    rc;
    ngx_http_lua_loc_conf_t     *llcf;
    int                          timeout;

    ngx_http_lua_socket_upstream_t          *u;

    n = lua_gettop(L);
    if (n != 2 && n != 3) {
        return luaL_error(L, "ngx.socket connect: expecting 2 or 3 arguments "
                          "(including the object), but seen %d", n);
    }

    lua_getglobal(L, GLOBALS_SYMBOL_REQUEST);
    r = lua_touserdata(L, -1);
    lua_pop(L, 1);

    p = (u_char *) luaL_checklstring(L, 2, &len);

    if (n == 3) {
        port = luaL_checkinteger(L, 3);

        if (port < 0 || port > 65536) {
            lua_pushnil(L);
            lua_pushfstring(L, "bad port number: %d", port);
            return 2;
        }

    } else { /* n == 2 */
        port = 0;
    }

    host.data = ngx_palloc(r->pool, len + 1);
    if (host.data == NULL) {
        return luaL_error(L, "out of memory");
    }

    host.len = len;

    ngx_memcpy(host.data, p, len);
    host.data[len] = '\0';

    ngx_memzero(&url, sizeof(ngx_url_t));

    url.url.len = host.len;
    url.url.data = host.data;
    url.default_port = port;
    url.no_resolve = 1;

    if (ngx_parse_url(r->pool, &url) != NGX_OK) {
        lua_pushnil(L);

        if (url.err) {
            lua_pushfstring(L, "failed to parse host name \"%s\": %s",
                            host.data, url.err);

        } else {
            lua_pushfstring(L, "failed to parse host name \"%s\"", host.data);
        }

        return 2;
    }

    r->connection->single_connection = 0;

    lua_getfield(L, 1, "_ctx");
    u = lua_touserdata(L, -1);
    lua_pop(L, 1);

    if (u) {
        if (u->peer.connection) {
            ngx_log_debug0(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                           "lua socket reconnect without shutting down");

            ngx_http_lua_socket_finalize(r, u);
        }

        ngx_log_debug0(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                       "lua reuse socket upstream ctx");

    } else {
        u = lua_newuserdata(L, sizeof(ngx_http_lua_socket_upstream_t));
        if (u == NULL) {
            return luaL_error(L, "out of memory");
        }

        lua_setfield(L, 1, "_ctx");
    }

    ngx_memzero(u, sizeof(ngx_http_lua_socket_upstream_t));

    lua_getfield(L, 1, "_tm");
    timeout = lua_tointeger(L, -1);
    lua_pop(L, 1);

    if (timeout > 0) {
        u->timeout = (ngx_msec_t) timeout;

    } else {
        llcf = ngx_http_get_module_loc_conf(r, ngx_http_lua_module);
        u->timeout = llcf->connect_timeout;
    }

    ngx_log_debug1(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                   "lua socket connect timeout: %M", u->timeout);

    u->request = r; /* set the controlling request */

    u->resolved = ngx_pcalloc(r->pool, sizeof(ngx_http_upstream_resolved_t));
    if (u->resolved == NULL) {
        return luaL_error(L, "out of memory");
    }

    if (url.addrs && url.addrs[0].sockaddr) {
        ngx_log_debug0(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                       "lua socket network address given directly");

        u->resolved->sockaddr = url.addrs[0].sockaddr;
        u->resolved->socklen = url.addrs[0].socklen;
        u->resolved->naddrs = 1;
        u->resolved->host = url.addrs[0].name;

    } else {
        u->resolved->host = host;
        u->resolved->port = (in_port_t) port;
    }

    if (u->resolved->sockaddr) {
        rc = ngx_http_lua_socket_resolve_retval_handler(r, u, L);
        if (rc == NGX_AGAIN) {
            return lua_yield(L, 0);
        }

        return rc;
    }

    clcf = ngx_http_get_module_loc_conf(r, ngx_http_core_module);

    temp.name = host;
    rctx = ngx_resolve_start(clcf->resolver, &temp);
    if (rctx == NULL) {
        u->ft_type |= NGX_HTTP_LUA_SOCKET_FT_RESOLVER;
        lua_pushnil(L);
        lua_pushliteral(L, "failed to start the resolver");
        return 2;
    }

    if (rctx == NGX_NO_RESOLVER) {
        u->ft_type |= NGX_HTTP_LUA_SOCKET_FT_RESOLVER;
        lua_pushnil(L);
        lua_pushfstring(L, "no resolver defined to resolve \"%s\"", host.data);
        return 2;
    }

    rctx->name = host;
    rctx->type = NGX_RESOLVE_A;
    rctx->handler = ngx_http_lua_socket_resolve_handler;
    rctx->data = u;
    rctx->timeout = clcf->resolver_timeout;

    u->resolved->ctx = rctx;

    saved_top = lua_gettop(L);

    if (ngx_resolve_name(rctx) != NGX_OK) {
        ngx_log_debug0(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                       "lua socket fail to run resolver immediately");

        u->ft_type |= NGX_HTTP_LUA_SOCKET_FT_RESOLVER;

        u->resolved->ctx = NULL;
        lua_pushnil(L);
        lua_pushfstring(L, "%s could not be resolved", host.data);

        return 2;
    }

    ctx = ngx_http_get_module_ctx(r, ngx_http_lua_module);

    if (u->waiting == 1) {
        /* resolved and already connecting */
        return lua_yield(L, 0);
    }

    n = lua_gettop(L) - saved_top;
    if (n) {
        /* errors occurred during resolving or connecting
         * or already connected */
        return n;
    }

    /* still resolving */

    ctx->data = u;
    ctx->socket_busy = 1;
    ctx->socket_ready = 0;

    u->waiting = 1;
    u->prepare_retvals = ngx_http_lua_socket_resolve_retval_handler;

    if (ctx->entered_content_phase) {
        r->write_event_handler = ngx_http_lua_content_wev_handler;
    }

    return lua_yield(L, 0);
}


static void
ngx_http_lua_socket_resolve_handler(ngx_resolver_ctx_t *ctx)
{
    ngx_http_request_t                  *r;
    ngx_http_upstream_resolved_t        *ur;
    ngx_http_lua_ctx_t                  *lctx;
    lua_State                           *L;
    ngx_http_lua_socket_upstream_t      *u;
    u_char                              *p;
    size_t                               len;
    struct sockaddr_in                  *sin;
    ngx_uint_t                           i;
    unsigned                             waiting;

    u = ctx->data;
    r = u->request;
    ur = u->resolved;

    ngx_log_debug0(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                   "lua socket resolve handler");

    lctx = ngx_http_get_module_ctx(r, ngx_http_lua_module);

    L = lctx->cc;

    lctx->socket_busy = 0;
    lctx->socket_ready = 1;

    waiting = u->waiting;

    if (ctx->state) {
        ngx_log_debug2(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                       "lua socket resolver error: %s (waiting: %d)",
                       ngx_resolver_strerror(ctx->state), (int) u->waiting);

        lua_pushnil(L);
        lua_pushlstring(L, (char *) ctx->name.data, ctx->name.len);
        lua_pushfstring(L, " could not be resolved (%d: %s)",
                        (int) ctx->state,
                        ngx_resolver_strerror(ctx->state));
        lua_concat(L, 2);

        u->prepare_retvals = ngx_http_lua_socket_error_retval_handler;
        ngx_http_lua_socket_handle_error(r, u,
                                         NGX_HTTP_LUA_SOCKET_FT_RESOLVER);

        if (waiting) {
            ngx_http_run_posted_requests(r->connection);
        }

        return;
    }

    ur->naddrs = ctx->naddrs;
    ur->addrs = ctx->addrs;

#if (NGX_DEBUG)
    {
    in_addr_t   addr;
    ngx_uint_t  i;

    for (i = 0; i < ctx->naddrs; i++) {
        dd("addr i: %d %p", (int) i,  &ctx->addrs[i]);

        addr = ntohl(ctx->addrs[i]);

        ngx_log_debug4(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                       "name was resolved to %ud.%ud.%ud.%ud",
                       (addr >> 24) & 0xff, (addr >> 16) & 0xff,
                       (addr >> 8) & 0xff, addr & 0xff);
    }
    }
#endif

    if (ur->naddrs == 0) {
        u->ft_type |= NGX_HTTP_LUA_SOCKET_FT_RESOLVER;

        lua_pushnil(L);
        lua_pushliteral(L, "name cannot be resolved to a address");
        return;
    }

    if (ur->naddrs == 1) {
        i = 0;

    } else {
        i = ngx_random() % ur->naddrs;
    }

    dd("selected addr index: %d", (int) i);

    len = NGX_INET_ADDRSTRLEN + sizeof(":65536") - 1;

    p = ngx_pnalloc(r->pool, len);
    if (p == NULL) {
        u->ft_type |= NGX_HTTP_LUA_SOCKET_FT_RESOLVER;

        lua_pushnil(L);
        lua_pushliteral(L, "out of memory");
        return;
    }

    len = ngx_inet_ntop(AF_INET, &ur->addrs[i], p, NGX_INET_ADDRSTRLEN);
    len = ngx_sprintf(&p[len], ":%d", ur->port) - p;

    sin = ngx_pcalloc(r->pool, sizeof(struct sockaddr_in));
    if (sin == NULL) {
        u->ft_type |= NGX_HTTP_LUA_SOCKET_FT_RESOLVER;

        lua_pushnil(L);
        lua_pushliteral(L, "out of memory");
        return;
    }

    sin->sin_family = AF_INET;
    sin->sin_port = htons(ur->port);
    sin->sin_addr.s_addr = ur->addrs[i];

    ur->sockaddr = (struct sockaddr *) sin;
    ur->socklen = sizeof(struct sockaddr_in);

    ur->host.data = p;
    ur->host.len = len;
    ur->naddrs = 1;

    ur->ctx = NULL;

    ngx_resolve_name_done(ctx);

    u->waiting = 0;

    (void) ngx_http_lua_socket_resolve_retval_handler(r, u, L);
}


static int
ngx_http_lua_socket_resolve_retval_handler(ngx_http_request_t *r,
    ngx_http_lua_socket_upstream_t *u, lua_State *L)
{
    ngx_http_lua_ctx_t              *ctx;
    ngx_http_lua_loc_conf_t         *llcf;
    ngx_peer_connection_t           *pc;
    ngx_connection_t                *c;
    ngx_http_cleanup_t              *cln;
    ngx_http_upstream_resolved_t    *ur;
    ngx_int_t                        rc;

    ngx_log_debug0(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                   "lua socket resolve retval handler");

    if (u->ft_type & NGX_HTTP_LUA_SOCKET_FT_RESOLVER) {
        return 2;
    }

    llcf = ngx_http_get_module_loc_conf(r, ngx_http_lua_module);

    u->conf = llcf;

    pc = &u->peer;

    pc->log = r->connection->log;
    pc->log_error = NGX_ERROR_ERR;

    ur = u->resolved;

    if (ur->sockaddr) {
        pc->sockaddr = ur->sockaddr;
        pc->socklen = ur->socklen;
        pc->name = &ur->host;

    } else {
        lua_pushnil(L);
        lua_pushliteral(L, "resolver not working");
        return 2;
    }

    pc->get = ngx_http_lua_socket_tcp_get_peer;

    rc = ngx_event_connect_peer(pc);

    cln = ngx_http_cleanup_add(r, 0);
    if (cln == NULL) {
        u->ft_type |= NGX_HTTP_LUA_SOCKET_FT_ERROR;
        lua_pushnil(L);
        lua_pushliteral(L, "out of memory");
        return 2;
    }

    cln->handler = ngx_http_lua_socket_cleanup;
    cln->data = u;
    u->cleanup = &cln->handler;

    ngx_log_debug1(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                   "lua tcp socket connect: %i", rc);

    if (rc == NGX_ERROR) {
        u->ft_type |= NGX_HTTP_LUA_SOCKET_FT_ERROR;
        lua_pushnil(L);
        lua_pushliteral(L, "connect peer error");
        return 2;
    }

    if (rc == NGX_BUSY) {
        u->ft_type |= NGX_HTTP_LUA_SOCKET_FT_ERROR;
        lua_pushnil(L);
        lua_pushliteral(L, "no live connection");
        return 2;
    }

    if (rc == NGX_DECLINED) {
        dd("socket errno: %d", (int) ngx_socket_errno);
        u->ft_type |= NGX_HTTP_LUA_SOCKET_FT_ERROR;
        u->socket_errno = ngx_socket_errno;
        return ngx_http_lua_socket_error_retval_handler(r, u, L);
    }

    /* rc == NGX_OK || rc == NGX_AGAIN */

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

    ctx->data = u;

    if (rc == NGX_OK) {
        ngx_log_debug1(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                       "lua socket connected: fd:%d", (int) c->fd);

        /* We should delete the current write/read event
         * here because the socket object may not be used immediately
         * on the Lua land, thus causing hot spin around level triggered
         * event poll and wasting CPU cycles. */

        if (ngx_handle_write_event(c->write, 0) != NGX_OK) {
            ngx_http_lua_socket_handle_error(r, u,
                                             NGX_HTTP_LUA_SOCKET_FT_ERROR);
            lua_pushnil(L);
            lua_pushliteral(L, "failed to handle write event");
            return 2;
        }

        if (ngx_handle_read_event(c->read, 0) != NGX_OK) {
            ngx_http_lua_socket_handle_error(r, u,
                                             NGX_HTTP_LUA_SOCKET_FT_ERROR);
            lua_pushnil(L);
            lua_pushliteral(L, "failed to handle write event");
            return 2;
        }

        ctx = ngx_http_get_module_ctx(r, ngx_http_lua_module);

        ctx->socket_busy = 0;
        ctx->socket_ready = 1;

        u->read_event_handler = ngx_http_lua_socket_dummy_handler;
        u->write_event_handler = ngx_http_lua_socket_dummy_handler;

        lua_pushinteger(L, 1);
        lua_pushnil(L);
        return 2;
    }

    /* rc == NGX_AGAIN */

    /* TODO we should also support socket:settimeout() here */
    ngx_add_timer(c->write, u->timeout);

    if (ctx->entered_content_phase) {
        r->write_event_handler = ngx_http_lua_content_wev_handler;
    }

    u->waiting = 1;

    u->prepare_retvals = ngx_http_lua_socket_tcp_connect_retval_handler;

    ctx->socket_busy = 1;
    ctx->socket_ready = 0;

    if (ctx->entered_content_phase) {
        r->write_event_handler = ngx_http_lua_content_wev_handler;
    }

    return NGX_AGAIN;
}


static int
ngx_http_lua_socket_error_retval_handler(ngx_http_request_t *r,
    ngx_http_lua_socket_upstream_t *u, lua_State *L)
{
    u_char           errstr[NGX_MAX_ERROR_STR];
    u_char          *p;

    ngx_http_lua_socket_finalize(r, u);

    ngx_log_debug0(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                   "lua socket error retval handler");

    if (u->ft_type & NGX_HTTP_LUA_SOCKET_FT_RESOLVER) {
        return 2;
    }

    lua_pushnil(L);

    if (u->ft_type & NGX_HTTP_LUA_SOCKET_FT_TIMEOUT) {
        lua_pushliteral(L, "timeout");

    } else if (u->ft_type & NGX_HTTP_LUA_SOCKET_FT_CLOSED) {
        lua_pushliteral(L, "closed");

    } else if (u->ft_type & NGX_HTTP_LUA_SOCKET_FT_BUFTOOSMALL) {
        lua_pushliteral(L, "buffer too small");

    } else {

        if (u->socket_errno) {
            p = ngx_strerror(u->socket_errno, errstr, sizeof(errstr));
            /* for compatibility with LuaSocket */
            ngx_strlow(errstr, errstr, p - errstr);
            lua_pushlstring(L, (char *) errstr, p - errstr);

        } else {
            lua_pushliteral(L, "error");
        }
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
    int                                  n;
    ngx_str_t                            pat;
    lua_Integer                          bytes;
    char                                *p;
    int                                  typ;
    int                                  timeout;

    n = lua_gettop(L);
    if (n != 1 && n != 2) {
        return luaL_error(L, "expecting 1 or 2 arguments "
                          "(including the object), but got %d", n);
    }

    lua_getglobal(L, GLOBALS_SYMBOL_REQUEST);
    r = lua_touserdata(L, -1);
    lua_pop(L, 1);

    ngx_log_debug0(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                   "lua socket calling receive() method");

    luaL_checktype(L, 1, LUA_TTABLE);

    lua_getfield(L, 1, "_ctx");
    u = lua_touserdata(L, -1);

    if (u == NULL || u->peer.connection == NULL || u->ft_type || u->eof) {
        lua_pushnil(L);
        lua_pushliteral(L, "closed");
        return 2;
    }

    lua_getfield(L, 1, "_tm");
    timeout = lua_tointeger(L, -1);
    lua_pop(L, 1);

    if (timeout > 0) {
        u->timeout = (ngx_msec_t) timeout;

    } else {
        u->timeout = u->conf->read_timeout;
    }

    ngx_log_debug1(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                   "lua socket read timeout: %M", u->timeout);

    if (n > 1) {
        if (lua_isnumber(L, 2)) {
            typ = LUA_TNUMBER;

        } else {
            typ = lua_type(L, 2);
        }

        switch (typ) {
        case LUA_TSTRING:
            pat.data = (u_char *) luaL_checklstring(L, 2, &pat.len);
            if (pat.len != 2 || pat.data[0] != '*') {
                p = (char *) lua_pushfstring(L, "bad pattern argument: %s",
                                    (char *) pat.data);

                return luaL_argerror(L, 2, p);
            }

            switch (pat.data[1]) {
            case 'l':
                u->input_filter = ngx_http_lua_socket_read_line;
                break;

            case 'a':
                u->input_filter = ngx_http_lua_socket_read_all;
                break;

            default:
                return luaL_argerror(L, 2, "bad pattern argument");
                break;
            }

            break;

        case LUA_TNUMBER:
            bytes = lua_tointeger(L, 2);
            if (bytes <= 0) {
                return luaL_argerror(L, 2, "bad pattern argument");
            }

            u->input_filter = ngx_http_lua_socket_read_chunk;
            u->length = (size_t) bytes;
            u->rest = u->length;
            break;

        default:
            return luaL_argerror(L, 2, "bad pattern argument");
            break;
        }

    } else {
        u->input_filter = ngx_http_lua_socket_read_line;
    }

    u->input_filter_ctx = u;

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
    u->waiting = 0;

    rc = ngx_http_lua_socket_read(r, u);

    if (rc == NGX_ERROR) {
        dd("read failed: %d", (int) u->ft_type);
        rc = ngx_http_lua_socket_tcp_receive_retval_handler(r, u, L);
        dd("tcp receive retval returned: %d", (int) rc);
        return rc;
    }

    if (rc == NGX_OK) {

        ngx_log_debug0(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                       "lua socket receive done in a single run");

        return ngx_http_lua_socket_tcp_receive_retval_handler(r, u, L);
    }

    /* rc == NGX_AGAIN */

    ctx = ngx_http_get_module_ctx(r, ngx_http_lua_module);

    u->read_event_handler = ngx_http_lua_socket_read_handler;
    u->write_event_handler = ngx_http_lua_socket_dummy_handler;

    if (ctx->entered_content_phase) {
        r->write_event_handler = ngx_http_lua_content_wev_handler;
    }

    u->waiting = 1;

    ctx->data = u;
    u->prepare_retvals = ngx_http_lua_socket_tcp_receive_retval_handler;

    ctx->socket_busy = 1;
    ctx->socket_ready = 0;

    return lua_yield(L, 0);
}


static ngx_int_t
ngx_http_lua_socket_read_chunk(void *data, ssize_t bytes)
{
    ngx_http_lua_socket_upstream_t      *u = data;

    ngx_buf_t                   *b;
    ngx_http_lua_ctx_t          *ctx;
    ngx_http_request_t          *r;

    r = u->request;

    ngx_log_debug0(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                   "lua socket read chunk");

    if (!u->luabuf_inited) {
        ctx = ngx_http_get_module_ctx(r, ngx_http_lua_module);
        luaL_buffinit(ctx->cc, &u->luabuf);
        u->luabuf_inited = 1;
    }

    if (bytes == 0) {
        u->ft_type |= NGX_HTTP_LUA_SOCKET_FT_CLOSED;
        return NGX_ERROR;
    }

    b = &u->buffer;

    if (bytes >= (ssize_t) u->rest) {

        luaL_addlstring(&u->luabuf, (char *) b->pos, u->rest);

        b->pos += u->rest;
        u->rest = 0;

        return NGX_OK;
    }

    /* bytes < u->rest */

    luaL_addlstring(&u->luabuf, (char *) b->pos, bytes);

    b->pos += bytes;
    u->rest -= bytes;

    return NGX_AGAIN;
}


static ngx_int_t
ngx_http_lua_socket_read_all(void *data, ssize_t bytes)
{
    ngx_http_lua_socket_upstream_t      *u = data;

    ngx_buf_t                   *b;
    ngx_http_lua_ctx_t          *ctx;
    ngx_http_request_t          *r;

    r = u->request;

    ngx_log_debug0(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                   "lua socket read all");

    if (!u->luabuf_inited) {
        ctx = ngx_http_get_module_ctx(r, ngx_http_lua_module);
        luaL_buffinit(ctx->cc, &u->luabuf);
        u->luabuf_inited = 1;
    }

    if (bytes == 0) {
        return NGX_OK;
    }

    b = &u->buffer;

    luaL_addlstring(&u->luabuf, (char *) b->pos, bytes);

    b->pos += bytes;

    return NGX_AGAIN;
}


static ngx_int_t
ngx_http_lua_socket_read_line(void *data, ssize_t bytes)
{
    ngx_http_lua_socket_upstream_t      *u = data;

    ngx_buf_t                   *b;
    u_char                      *begin;
    u_char                      *dst;
    ngx_http_lua_ctx_t          *ctx;
    ngx_http_request_t          *r;
    u_char                       c;

    ngx_log_debug0(NGX_LOG_DEBUG_HTTP, u->request->connection->log, 0,
                   "lua socket read line");

    if (bytes == 0) {
        u->ft_type |= NGX_HTTP_LUA_SOCKET_FT_CLOSED;
        return NGX_ERROR;
    }

    if (!u->luabuf_inited) {
        r = u->request;
        ctx = ngx_http_get_module_ctx(r, ngx_http_lua_module);
        luaL_buffinit(ctx->cc, &u->luabuf);
        u->luabuf_inited = 1;
    }

    b = &u->buffer;
    begin = b->pos;
    dst = begin;

    while (bytes--) {

        c = *b->pos++;

        switch (c) {
        case '\n':
            ngx_log_debug2(NGX_LOG_DEBUG_HTTP, u->request->connection->log, 0,
                   "lua socket read the final line part: %*s",
                   dst - begin, begin);

            luaL_addlstring(&u->luabuf, (char *) begin, dst - begin);
            return NGX_OK;

        case '\r':
            /* ignore it */
            break;

        default:
            *dst++ = c;
            break;
        }
    }

    ngx_log_debug2(NGX_LOG_DEBUG_HTTP, u->request->connection->log, 0,
                   "lua socket read partial line data: %*s",
                   dst - begin, begin);

    luaL_addlstring(&u->luabuf, (char *) begin, dst - begin);

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

    ngx_log_debug1(NGX_LOG_DEBUG_HTTP, c->log, 0,
                   "lua socket read data: waiting: %d", (int) u->waiting);

    b = &u->buffer;
    read = 0;

    for ( ;; ) {

        size = b->last - b->pos;

        if (size || u->eof) {

            rc = u->input_filter(u->input_filter_ctx, size);

            if (rc == NGX_OK) {
                ngx_log_debug4(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                               "lua socket receive done: wait:%d, eof:%d, "
                               "uri:\"%V?%V\"", (int) u->waiting, (int) u->eof,
                               &r->uri, &r->args);

                if (ngx_handle_read_event(rev, 0) != NGX_OK) {
                    ngx_http_lua_socket_handle_error(r, u,
                                     NGX_HTTP_LUA_SOCKET_FT_ERROR);
                    return NGX_ERROR;
                }

                ngx_http_lua_socket_handle_success(r, u);
                return NGX_OK;
            }

            if (rc == NGX_ERROR) {
                dd("input filter error: ft_type:%d waiting:%d",
                        (int) u->ft_type, (int) u->waiting);

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

#if 1
        if (b->pos > b->start && b->pos == b->last) {
            b->pos = b->start;
            b->last = b->start;
        }
#endif

        size = b->end - b->last;

        if (size == 0) {
            /* TODO: flush the buffer onto luaL_Buffer */
            ngx_http_lua_socket_handle_error(r, u,
                                         NGX_HTTP_LUA_SOCKET_FT_BUFTOOSMALL);

            return NGX_ERROR;
        }

        n = c->recv(c, b->last, size);
        read = 1;

        ngx_log_debug3(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                       "lua socket recv returned %d: \"%V?%V\"",
                       (int) n, &r->uri, &r->args);

        if (n == NGX_AGAIN) {
            rc = NGX_AGAIN;
            dd("socket recv busy");
            break;
        }

        if (n == 0) {
            u->eof = 1;

            ngx_log_debug0(NGX_LOG_DEBUG_HTTP, u->request->connection->log, 0,
                           "lua socket closed");

            continue;
        }

        if (n == NGX_ERROR) {
            ngx_http_lua_socket_handle_error(r, u,
                                             NGX_HTTP_LUA_SOCKET_FT_ERROR);
            return NGX_ERROR;
        }

        b->last += n;
    }

    if (ngx_handle_read_event(rev, 0) != NGX_OK) {
        ngx_http_lua_socket_handle_error(r, u,
                                         NGX_HTTP_LUA_SOCKET_FT_ERROR);
        return NGX_ERROR;
    }

    if (rev->active) {
        ngx_add_timer(rev, u->timeout);

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
    int                                  timeout;

    /* TODO: add support for the optional "i" and "j" arguments */

    if (lua_gettop(L) != 2) {
        return luaL_error(L, "expecting two arguments (one for the object), "
                          "but got %d", lua_gettop(L));
    }

    lua_getglobal(L, GLOBALS_SYMBOL_REQUEST);
    r = lua_touserdata(L, -1);
    lua_pop(L, 1);

    luaL_checktype(L, 1, LUA_TTABLE);

    lua_getfield(L, 1, "_ctx");
    u = lua_touserdata(L, -1);
    lua_pop(L, 1);

    if (u == NULL || u->peer.connection == NULL || u->ft_type || u->eof) {
        lua_pushnil(L);
        lua_pushliteral(L, "closed");
        return 2;
    }

    lua_getfield(L, 1, "_tm");
    timeout = lua_tointeger(L, -1);
    lua_pop(L, 1);

    if (timeout > 0) {
        u->timeout = (ngx_msec_t) timeout;

    } else {
        u->timeout = u->conf->send_timeout;
    }

    ngx_log_debug1(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                   "lua socket send timeout: %M", u->timeout);

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

    dd("socket send returned %d", (int) rc);

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

    if (ctx->entered_content_phase) {
        r->write_event_handler = ngx_http_lua_content_wev_handler;
    }

    u->waiting = 1;

    ctx->data = u;
    u->prepare_retvals = ngx_http_lua_socket_tcp_send_retval_handler;

    ctx->socket_busy = 1;
    ctx->socket_ready = 0;

    return lua_yield(L, 0);
}


static int
ngx_http_lua_socket_tcp_send_retval_handler(ngx_http_request_t *r,
    ngx_http_lua_socket_upstream_t *u, lua_State *L)
{
    ngx_log_debug0(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                   "lua socket send return value handler");

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
    int         n;

    ngx_log_debug0(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                   "lua socket receive return value handler");

    if (u->ft_type) {
        n = ngx_http_lua_socket_error_retval_handler(r, u, L);
        if (u->luabuf_inited) {
            luaL_pushresult(&u->luabuf);
            u->luabuf_inited = 0;

        } else {
            lua_pushliteral(L, "");
        }

        return n + 1;
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
    ngx_http_request_t                  *r;
    ngx_http_lua_socket_upstream_t      *u;

    if (lua_gettop(L) != 1) {
        return luaL_error(L, "ngx.socket close: expecting 1 argument "
                          "(including the object) but seen %d", lua_gettop(L));
    }

    lua_getglobal(L, GLOBALS_SYMBOL_REQUEST);
    r = lua_touserdata(L, -1);
    lua_pop(L, 1);

    luaL_checktype(L, 1, LUA_TTABLE);

    lua_getfield(L, 1, "_ctx");
    u = lua_touserdata(L, -1);
    lua_pop(L, 1);

    if (u == NULL || u->peer.connection == NULL || u->ft_type || u->eof) {
        lua_pushnil(L);
        lua_pushliteral(L, "closed");
        return 2;
    }

    ngx_http_lua_socket_finalize(r, u);

    lua_pushinteger(L, 1);
    lua_pushnil(L);
    return 2;
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
    int          n;

    n = lua_gettop(L);

    if (n < 2) {
        return luaL_error(L, "ngx.socket settimout: expecting at least 2 "
                          "arguments (including the object) but seen %d",
                          lua_gettop(L));
    }

    lua_settop(L, 2);
    lua_setfield(L, 1, "_tm");

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

    ngx_log_debug3(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                   "lua socket handler for \"%V?%V\", wev %d", &r->uri,
                   &r->args, (int) ev->write);

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

    ngx_log_debug0(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                   "lua socket send data");

    rc = ngx_output_chain(&u->output, u->request_sent ? NULL : u->request_bufs);

    dd("output chain returned: %d", (int) rc);

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
        u->read_event_handler = ngx_http_lua_socket_dummy_handler;

        ngx_add_timer(c->write, u->timeout);

        if (ngx_handle_write_event(c->write, u->conf->send_lowat) != NGX_OK) {
            ngx_http_lua_socket_handle_error(r, u,
                         NGX_HTTP_LUA_SOCKET_FT_ERROR);
            return NGX_ERROR;
        }

        return NGX_AGAIN;
    }

    /* rc == NGX_OK */

    ngx_log_debug1(NGX_LOG_DEBUG_HTTP, c->log, 0,
            "lua socket sent all the data: buffered 0x%d", (int) c->buffered);

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

#if 0
    if (u->eof) {
        ngx_http_lua_socket_finalize(r, u);
    }
#endif

    if (u->waiting) {
        u->waiting = 0;

        ctx = ngx_http_get_module_ctx(r, ngx_http_lua_module);

        ctx->socket_busy = 0;
        ctx->socket_ready = 1;

        ngx_log_debug0(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                       "lua socket waking up the current request");

        ngx_http_post_request(r, NULL);
    }
}


static void
ngx_http_lua_socket_handle_error(ngx_http_request_t *r,
    ngx_http_lua_socket_upstream_t *u, ngx_uint_t ft_type)
{
    ngx_http_lua_ctx_t          *ctx;

    ngx_log_debug0(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                   "lua socket handle error");

    u->ft_type |= ft_type;
    ngx_http_lua_socket_finalize(r, u);

    if (u->waiting) {
        u->waiting = 0;

        ctx = ngx_http_get_module_ctx(r, ngx_http_lua_module);

        ctx->socket_busy = 0;
        ctx->socket_ready = 1;

        ngx_log_debug0(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                       "lua socket waking up the current request");

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
    ngx_int_t                    rc;
    ngx_connection_t            *c;

    c = u->peer.connection;

    if (c->write->timedout) {
        ngx_http_lua_socket_handle_error(r, u, NGX_HTTP_LUA_SOCKET_FT_TIMEOUT);
        return;
    }

    rc = ngx_http_lua_socket_test_connect(c);
    if (rc != NGX_OK) {
        if (rc > 0) {
            u->socket_errno = (ngx_err_t) rc;
        }

        ngx_http_lua_socket_handle_error(r, u, NGX_HTTP_LUA_SOCKET_FT_ERROR);
        return;
    }

    ngx_log_debug0(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                   "lua socket connected");

    /* We should delete the current write/read event
     * here because the socket object may not be used immediately
     * on the Lua land, thus causing hot spin around level triggered
     * event poll and wasting CPU cycles. */

    if (ngx_handle_write_event(c->write, 0) != NGX_OK) {
        ngx_http_lua_socket_handle_error(r, u, NGX_HTTP_LUA_SOCKET_FT_ERROR);
        return;
    }

    if (ngx_handle_read_event(c->read, 0) != NGX_OK) {
        ngx_http_lua_socket_handle_error(r, u, NGX_HTTP_LUA_SOCKET_FT_ERROR);
        return;
    }

    ctx = ngx_http_get_module_ctx(r, ngx_http_lua_module);

    ctx->socket_busy = 0;
    ctx->socket_ready = 1;

    u->read_event_handler = ngx_http_lua_socket_dummy_handler;
    u->write_event_handler = ngx_http_lua_socket_dummy_handler;

    if (c->write->timer_set) {
        ngx_del_timer(c->write);
    }

    ngx_log_debug0(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                   "lua socket waking up the current request");

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
                   "lua finalize socket");

    if (u->cleanup) {
        *u->cleanup = NULL;
        u->cleanup = NULL;
    }

    if (u->resolved && u->resolved->ctx) {
        ngx_resolve_name_done(u->resolved->ctx);
        u->resolved->ctx = NULL;
    }

    if (u->peer.free) {
        u->peer.free(&u->peer, u->peer.data, 0);
    }

    if (u->peer.connection) {
        ngx_log_debug0(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                       "lua close socket connection");

        ngx_close_connection(u->peer.connection);
    }

    if (u->buffer.start != NULL) {
        ngx_pfree(r->pool, u->buffer.start);
        u->buffer.start = NULL;
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
            (void) ngx_connection_error(c, err, "connect() failed");
            return err;
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


static int
ngx_http_lua_socket_tcp_receiveuntil(lua_State *L)
{
    ngx_http_request_t                  *r;
    int                                  n;
    ngx_str_t                            pat;
    ngx_int_t                            rc;
    size_t                               size;

    ngx_http_lua_socket_compiled_pattern_t     *cp;

    n = lua_gettop(L);
    if (n != 2) {
        return luaL_error(L, "expecting 2 arguments "
                          "(including the object), but got %d", n);
    }

    lua_getglobal(L, GLOBALS_SYMBOL_REQUEST);
    r = lua_touserdata(L, -1);
    lua_pop(L, 1);

    ngx_log_debug0(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                   "lua socket calling receiveuntil() method");

    luaL_checktype(L, 1, LUA_TTABLE);

    pat.data = (u_char *) luaL_checklstring(L, 2, &pat.len);
    if (pat.len == 0) {
        lua_pushnil(L);
        lua_pushliteral(L, "pattern is empty");
        return 2;
    }

    size = sizeof(ngx_http_lua_socket_compiled_pattern_t);

    cp = lua_newuserdata(L, size);
    if (cp == NULL) {
        return luaL_error(L, "out of memory");
    }

    lua_createtable(L, 0 /* narr */, 1 /* nrec */);
    lua_pushcfunction(L, ngx_http_lua_socket_cleanup_compiled_pattern);
    lua_setfield(L, -2, "__gc");
    lua_setmetatable(L, -2);

    ngx_memzero(cp, size);

    rc = ngx_http_lua_socket_compile_pattern(pat.data, pat.len, cp,
                                             r->connection->log);

    if (rc != NGX_OK) {
        lua_pushnil(L);
        lua_pushliteral(L, "failed to compile pattern");
        return 2;
    }

    lua_pushcclosure(L, ngx_http_lua_socket_receiveuntil_iterator, 3);
    return 1;
}


static int
ngx_http_lua_socket_receiveuntil_iterator(lua_State *L)
{
    ngx_http_request_t                  *r;
    ngx_http_lua_socket_upstream_t      *u;
    ngx_int_t                            rc;
    ngx_http_lua_ctx_t                  *ctx;
    lua_Integer                          bytes;
    int                                  timeout;
    int                                  n;

    ngx_http_lua_socket_compiled_pattern_t     *cp;

    n = lua_gettop(L);
    if (n > 1) {
        return luaL_error(L, "expecting 0 or 1 arguments, "
                          "but seen %d", n);
    }

    if (n >= 1) {
        bytes = luaL_checkinteger(L, 1);
        if (bytes < 0) {
            bytes = 0;
        }

    } else {
        bytes = 0;
    }

    lua_getfield(L, lua_upvalueindex(1), "_ctx");
    u = lua_touserdata(L, -1);
    lua_pop(L, 1);

    if (u == NULL || u->peer.connection == NULL || u->ft_type || u->eof) {
        lua_pushnil(L);
        lua_pushliteral(L, "closed");
        return 2;
    }

    r = u->request;

    ngx_log_debug0(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                   "lua socket receiveuntil iterator");

    lua_getfield(L, lua_upvalueindex(1), "_tm");
    timeout = lua_tointeger(L, -1);
    lua_pop(L, 1);

    if (timeout > 0) {
        u->timeout = (ngx_msec_t) timeout;

    } else {
        u->timeout = u->conf->read_timeout;
    }

    ngx_log_debug1(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                   "lua socket read timeout: %M", u->timeout);

    u->input_filter = ngx_http_lua_socket_read_until;

    cp = lua_touserdata(L, lua_upvalueindex(3));

    if (cp->state == -1) {
        cp->state = 0;

        lua_pushnil(L);
        lua_pushliteral(L, "done");
        lua_pushnil(L);
        return 3;
    }

    cp->upstream = u;

    cp->pattern.data = (u_char *) lua_tolstring(L, lua_upvalueindex(2),
                                                &cp->pattern.len);

    u->input_filter_ctx = cp;

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

    u->length = (size_t) bytes;
    u->rest = u->length;
    u->luabuf_inited = 0;
    u->waiting = 0;

    rc = ngx_http_lua_socket_read(r, u);

    if (rc == NGX_ERROR) {
        dd("read failed: %d", (int) u->ft_type);
        rc = ngx_http_lua_socket_tcp_receive_retval_handler(r, u, L);
        dd("tcp receive retval returned: %d", (int) rc);
        return rc;
    }

    if (rc == NGX_OK) {

        ngx_log_debug0(NGX_LOG_DEBUG_HTTP, u->request->connection->log, 0,
                       "lua socket receive done in a single run");

        return ngx_http_lua_socket_tcp_receive_retval_handler(r, u, L);
    }

    /* rc == NGX_AGAIN */

    ctx = ngx_http_get_module_ctx(r, ngx_http_lua_module);

    u->read_event_handler = ngx_http_lua_socket_read_handler;
    u->write_event_handler = ngx_http_lua_socket_dummy_handler;

    if (ctx->entered_content_phase) {
        r->write_event_handler = ngx_http_lua_content_wev_handler;
    }

    u->waiting = 1;

    ctx->data = u;
    u->prepare_retvals = ngx_http_lua_socket_tcp_receive_retval_handler;

    ctx->socket_busy = 1;
    ctx->socket_ready = 0;

    return lua_yield(L, 0);
}


static ngx_int_t
ngx_http_lua_socket_compile_pattern(u_char *data, size_t len,
    ngx_http_lua_socket_compiled_pattern_t *cp, ngx_log_t *log)
{
    size_t              i;
    size_t              prefix_len;
    size_t              size;
    unsigned            found;
    int                 cur_state, new_state;

    ngx_http_lua_dfa_edge_t         *edge;
    ngx_http_lua_dfa_edge_t        **last;

    cp->pattern.len = len;

    for (i = 1; i < len; i++) {
        prefix_len = 1;

        while (prefix_len <= len - i - 1) {

            if (ngx_memcmp(data, &data[i], prefix_len) == 0) {
                if (data[prefix_len] == data[i + prefix_len]) {
                    prefix_len++;
                    continue;
                }

                cur_state = i + prefix_len;
                new_state = prefix_len + 1;

                if (cp->recovering == NULL) {
                    size = sizeof(void *) * len;
                    cp->recovering = ngx_alloc(size, log);
                    if (cp->recovering == NULL) {
                        return NGX_ERROR;
                    }

                    ngx_memzero(cp->recovering, size);
                }

                edge = cp->recovering[cur_state];

                found = 0;

                if (edge == NULL) {
                    last = &cp->recovering[cur_state];

                } else {

                    for (; edge; edge = edge->next) {
                        last = &edge->next;

                        if (edge->chr == data[prefix_len]) {
                            found = 1;

                            if (edge->new_state < new_state) {
                                edge->new_state = new_state;
                            }

                            break;
                        }
                    }
                }

                if (!found) {
                    ngx_log_debug7(NGX_LOG_DEBUG_HTTP, log, 0,
                                   "lua socket read until recovering point: "
                                   "on state %d (%*s), if next is '%c', then "
                                   "recover to state %d (%*s)", cur_state,
                                   (size_t) cur_state, data, data[prefix_len],
                                   new_state, (size_t) new_state, data);

                    edge = ngx_alloc(sizeof(ngx_http_lua_dfa_edge_t), log);
                    edge->chr = data[prefix_len];
                    edge->new_state = new_state;
                    edge->next = NULL;

                    *last = edge;
                }

                break;
            }

            break;
        }
    }

    return NGX_OK;
}


static ngx_int_t
ngx_http_lua_socket_read_until(void *data, ssize_t bytes)
{
    ngx_http_lua_socket_compiled_pattern_t     *cp = data;

    ngx_http_lua_socket_upstream_t          *u;
    ngx_http_request_t                      *r;
    ngx_http_lua_ctx_t                      *ctx;
    ngx_buf_t                               *b;
    u_char                                   c;
    u_char                                  *pat;
    size_t                                   pat_len;
    int                                      i;
    int                                      state, old_state;
    ngx_http_lua_dfa_edge_t                 *edge;
    unsigned                                 matched;

    u = cp->upstream;
    r = u->request;

    ngx_log_debug0(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                   "lua socket read until");

    if (!u->luabuf_inited) {
        ctx = ngx_http_get_module_ctx(r, ngx_http_lua_module);
        luaL_buffinit(ctx->cc, &u->luabuf);
        u->luabuf_inited = 1;
    }

    if (bytes == 0) {
        u->ft_type |= NGX_HTTP_LUA_SOCKET_FT_CLOSED;
        return NGX_ERROR;
    }

    b = &u->buffer;

    pat = cp->pattern.data;
    pat_len = cp->pattern.len;
    state = cp->state;

    i = 0;
    while (i < bytes) {
        c = b->pos[i];

        dd("%d: read char %c, state: %d", i, c, state);

        if (c == pat[state]) {
            i++;
            state++;

            if (state == (int) pat_len) {
                /* already matched the whole pattern */
                dd("pat len: %d", (int) pat_len);

                b->pos += i;

                if (u->length) {
                    cp->state = -1;

                } else {
                    cp->state = 0;
                }

                return NGX_OK;
            }

            continue;
        }

        if (state == 0) {
            i++;
            luaL_addchar(&u->luabuf, c);
            continue;
        }

        matched = 0;

        if (cp->recovering) {
            for (edge = cp->recovering[state]; edge; edge = edge->next) {
                if (edge->chr == c) {
                    dd("matched '%c' and jumping to state %d", c, edge->new_state);
                    old_state = state;
                    state = edge->new_state;
                    matched = 1;
                    break;
                }
            }
        }

        if (!matched) {
#if 1
            dd("adding pending data: %.*s", state, pat);
            luaL_addlstring(&u->luabuf, (char *) pat, state);
#endif

            state = 0;
            continue;
        }

        /* matched */

        dd("adding pending data: %.*s", (int) (old_state + 1 - state),
           (char *) pat);

        luaL_addlstring(&u->luabuf, (char *) pat, old_state + 1 - state);
        i++;
        continue;
    }

    b->pos += i;
    cp->state = state;

    return NGX_AGAIN;
}


static int
ngx_http_lua_socket_cleanup_compiled_pattern(lua_State *L)
{
    ngx_http_lua_socket_compiled_pattern_t      *cp;

    ngx_http_lua_dfa_edge_t         *edge, *p;
    unsigned                         i;

    dd("cleanup compiled pattern");

    cp = lua_touserdata(L, 1);
    if (cp == NULL || cp->recovering == NULL) {
        return 0;
    }

    dd("pattern len: %d", (int) cp->pattern.len);

    for (i = 0; i < cp->pattern.len; i++) {
        edge = cp->recovering[i];

        while (edge) {
            p = edge;
            edge = edge->next;

            dd("freeing edge %p", p);

            ngx_free(p);

            dd("edge: %p", edge);
        }
    }

    return 0;
}

