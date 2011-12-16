#ifndef DDEBUG
#define DDEBUG 0
#endif
#include "ddebug.h"

#include "ngx_http_lua_uri.h"
#include "ngx_http_lua_util.h"


static int ngx_http_lua_ngx_req_set_uri(lua_State *L);


void
ngx_http_lua_inject_req_uri_api(lua_State *L)
{
    lua_pushcfunction(L, ngx_http_lua_ngx_req_set_uri);
    lua_setfield(L, -2, "set_uri");
}


static int
ngx_http_lua_ngx_req_set_uri(lua_State *L)
{
    ngx_http_request_t          *r;
    size_t                       len;
    u_char                      *p;
    int                          n;
    int                          jump = 0;
    ngx_http_lua_ctx_t          *ctx;

    n = lua_gettop(L);

    if (n != 1 && n != 2) {
        return luaL_error(L, "expecting 1 argument but seen %d", n);
    }

    lua_getglobal(L, GLOBALS_SYMBOL_REQUEST);
    r = lua_touserdata(L, -1);
    lua_pop(L, 1);

    if (n == 2) {
        luaL_checktype(L, 2, LUA_TBOOLEAN);
        jump = lua_toboolean(L, 2);
    }

    p = (u_char *) luaL_checklstring(L, 1, &len);

    if (len == 0) {
        return luaL_error(L, "attempt to use zero-length uri");
    }

    r->uri.data = ngx_palloc(r->pool, len);
    if (r->uri.data == NULL) {
        return luaL_error(L, "out of memory");
    }

    ngx_memcpy(r->uri.data, p, len);

    r->uri.len = len;

    r->internal = 1;
    r->valid_unparsed_uri = 0;

    ngx_http_set_exten(r);

    if (jump) {

        ctx = ngx_http_get_module_ctx(r, ngx_http_lua_module);

#if defined(DDEBUG) && DDEBUG
        if (ctx) {
            dd("rewrite: %d, access: %d, content: %d",
                    (int) ctx->entered_rewrite_phase,
                    (int) ctx->entered_access_phase,
                    (int) ctx->entered_content_phase);
        }
#endif

        if (ctx && ctx->entered_rewrite_phase
            && !ctx->entered_access_phase
            && !ctx->entered_content_phase)
        {
            r->uri_changed = 1;
            return lua_yield(L, 0);
        }

        return luaL_error(L, "attempt to call ngx.req.set_uri to do "
                "location jump in contexts other than rewrite_by_lua and "
                "rewrite_by_lua_file");
    }

    r->valid_location = 0;
    r->uri_changed = 0;

    return 0;
}

