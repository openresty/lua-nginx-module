#ifndef DDEBUG
#define DDEBUG 0
#endif
#include "ddebug.h"

#include "ngx_http_lua_socket.h"
#include "ngx_http_lua_contentby.h"


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
static void ngx_http_lua_socket_block_reading(ngx_http_request_t *r,
    ngx_http_lua_socket_upstream_t *u);
static void ngx_http_lua_socket_resume_handler(ngx_http_request_t *r,
    ngx_http_lua_socket_upstream_t *u);
static void ngx_http_lua_socket_cleanup(void *data);
static void ngx_http_lua_socket_finalize_request(ngx_http_request_t *r,
    ngx_http_lua_socket_upstream_t *u, ngx_int_t rc);
static void ngx_http_lua_socket_block_writing(ngx_http_request_t *r,
    ngx_http_lua_socket_upstream_t *u);


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

    ngx_http_lua_socket_upstream_t          *u;

    if (lua_gettop(L) != 3) {
        return luaL_error(L, "ngx.socket connect: expecting 2 argument but "
                "seen %d", lua_gettop(L));
    }

    lua_getglobal(L, GLOBALS_SYMBOL_REQUEST);
    r = lua_touserdata(L, -1);
    lua_pop(L, 1);

    ngx_memzero(&u, sizeof(ngx_url_t));

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

    u->write_event_handler = ngx_http_lua_socket_resume_handler;
    u->read_event_handler = ngx_http_lua_socket_resume_handler;

    c->pool = r->pool;
    c->log = r->connection->log;
    c->read->log = c->log;
    c->write->log = c->log;

    ctx = ngx_http_get_module_ctx(r, ngx_http_lua_module);

    if (rc == NGX_OK) {
        lua_pushinteger(L, 1);
        lua_pushnil(L);
        return 2;
    }

    if (ctx->entered_content_phase) {
        r->write_event_handler = ngx_http_lua_content_wev_handler;
    }

    ctx->socket_busy = 1;
    ctx->socket_ready = 0;

    return lua_yield(L, 0);
}


static int
ngx_http_lua_socket_tcp_receive(lua_State *L)
{
    /* TODO */
    return 0;
}


static int
ngx_http_lua_socket_tcp_send(lua_State *L)
{
    /* TODO */
    return 0;
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
    return NGX_OK;
}


static void
ngx_http_lua_socket_block_reading(ngx_http_request_t *r,
    ngx_http_lua_socket_upstream_t *u)
{
    ngx_log_debug0(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                   "lua socket reading blocked");

    if ((ngx_event_flags & NGX_USE_LEVEL_EVENT)
        && r->connection->read->active)
    {
        if (ngx_del_event(r->connection->read, NGX_READ_EVENT, 0) != NGX_OK) {
            /* XXX we should return errors to the Lua land */
            ngx_http_finalize_request(r, NGX_ERROR);
        }
    }
}


static void
ngx_http_lua_socket_block_writing(ngx_http_request_t *r,
    ngx_http_lua_socket_upstream_t *u)
{
    ngx_log_debug0(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                   "lua socket reading blocked");

    if ((ngx_event_flags & NGX_USE_LEVEL_EVENT)
        && r->connection->write->active)
    {
        if (ngx_del_event(r->connection->write, NGX_WRITE_EVENT, 0) != NGX_OK) {
            /* XXX we should return errors to the Lua land */
            ngx_http_finalize_request(r, NGX_ERROR);
        }
    }
}


static void
ngx_http_lua_socket_resume_handler(ngx_http_request_t *r,
    ngx_http_lua_socket_upstream_t *u)
{
    ngx_http_lua_ctx_t          *ctx;

    ctx = ngx_http_get_module_ctx(r, ngx_http_lua_module);

    ctx->socket_busy = 0;
    ctx->socket_ready = 1;

    u->read_event_handler = ngx_http_lua_socket_block_reading;
    u->write_event_handler = ngx_http_lua_socket_block_writing;

    r->write_event_handler(r);
}


static void
ngx_http_lua_socket_cleanup(void *data)
{
    ngx_http_lua_socket_upstream_t  *u = data;

    ngx_http_request_t  *r;

    r = u->request;

    ngx_log_debug1(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                   "cleanup lua socket upstream request: \"%V\"", &r->uri);

    ngx_http_lua_socket_finalize_request(r, u, NGX_DONE);
}


static void
ngx_http_lua_socket_finalize_request(ngx_http_request_t *r,
    ngx_http_lua_socket_upstream_t *u, ngx_int_t rc)
{
    ngx_log_debug1(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                   "finalize lua socket upstream request: %i", rc);

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

    ngx_http_finalize_request(r, rc);
}

