#ifndef DDEBUG
#define DDEBUG 0
#endif
#include "ddebug.h"

#include "ngx_http_lua_req_body.h"
#include "ngx_http_lua_util.h"


static int ngx_http_lua_ngx_req_read_body(lua_State *L);
static void ngx_http_lua_req_body_post_read(ngx_http_request_t *r);


void
ngx_http_lua_inject_req_body_api(lua_State *L)
{
    lua_pushcfunction(L, ngx_http_lua_ngx_req_read_body);
    lua_setfield(L, -2, "read_body");
}


static int
ngx_http_lua_ngx_req_read_body(lua_State *L) {
    ngx_http_request_t          *r;
    int                          n;
    ngx_http_lua_ctx_t          *ctx;
    ngx_int_t                    rc;

    n = lua_gettop(L);

    if (n != 0) {
        return luaL_error(L, "expecting 0 arguments but seen %d", n);
    }

    lua_getglobal(L, GLOBALS_SYMBOL_REQUEST);
    r = lua_touserdata(L, -1);
    lua_pop(L, 1);

    r->request_body_in_single_buf = 1;
    r->request_body_in_persistent_file = 1;
    r->request_body_in_clean_file = 1;

#if 0
    if (r->request_body_in_file_only) {
        r->request_body_file_log_level = 0;
    }
#endif

    ctx = ngx_http_get_module_ctx(r, ngx_http_lua_module);
    if (ctx == NULL) {
        return luaL_error(L, "request context is null");
    }

    ngx_log_debug0(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
            "lua start to read buffered request body");

    rc = ngx_http_read_client_request_body(r, ngx_http_lua_req_body_post_read);

    if (rc == NGX_ERROR || rc >= NGX_HTTP_SPECIAL_RESPONSE) {
        return luaL_error(L, "failed to read request body");
    }

    if (rc == NGX_AGAIN) {
        ngx_log_debug0(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                "lua read buffered request body requires I/O interruptions");

        ctx->waiting_more_body = 1;
        ctx->req_read_body_done = 0;

        return lua_yield(L, 0);
    }

    /* rc == NGX_OK */

    ctx->req_read_body_done = 0;

    ngx_log_debug0(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
            "lua has read buffered request body in a single run");

    return 0;
}


static void
ngx_http_lua_req_body_post_read(ngx_http_request_t *r)
{
    ngx_http_lua_ctx_t  *ctx;

    ngx_log_debug0(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
            "lua req body post read");

    r->read_event_handler = ngx_http_request_empty_handler;

    ctx = ngx_http_get_module_ctx(r, ngx_http_lua_module);
    ctx->req_read_body_done = 1;

#if defined(nginx_version) && nginx_version >= 8011
    r->main->count--;
#endif

    if (ctx->waiting_more_body) {
        ctx->waiting_more_body = 0;

        if (ctx->entered_content_phase) {
            ngx_http_lua_wev_handler(r);

        } else {
            ngx_http_core_run_phases(r);
        }
    }
}

