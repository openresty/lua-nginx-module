#ifndef DDEBUG
#define DDEBUG 0
#endif
#include "ddebug.h"

#include "ngx_http_lua_phase.h"

#include "ngx_http_lua_util.h"
#include "ngx_http_lua_ctx.h"

static int ngx_http_lua_ngx_get_phase(lua_State *L);


static int
ngx_http_lua_ngx_get_phase(lua_State *L)
{
    ngx_http_request_t          *r;
    ngx_http_lua_ctx_t          *ctx;
    
    lua_pushlightuserdata(L, &ngx_http_lua_request_key);
    lua_rawget(L, LUA_GLOBALSINDEX);
    r = lua_touserdata(L, -1);
    lua_pop(L, 1);

    /* If we have no request object, assume we are called from the "init" phase. */
    if (r == NULL) {
        lua_pushlstring(L, (char *) "init", sizeof("init"));
        return 1;
    }

    ctx = ngx_http_get_module_ctx(r, ngx_http_lua_module);
    if (ctx == NULL) {
        return luaL_error(L, "no request ctx found");
    }

    switch (ctx->context) {
        case NGX_HTTP_LUA_CONTEXT_SET: 
            lua_pushlstring(L, (char *) "set", sizeof("set"));
            break;
        case NGX_HTTP_LUA_CONTEXT_REWRITE:
            lua_pushlstring(L, (char *) "rewrite", sizeof("rewrite"));
            break;
        case NGX_HTTP_LUA_CONTEXT_ACCESS:
            lua_pushlstring(L, (char *) "access", sizeof("access"));
            break;
        case NGX_HTTP_LUA_CONTEXT_CONTENT:
            lua_pushlstring(L, (char *) "content", sizeof("content"));
            break;
        case NGX_HTTP_LUA_CONTEXT_LOG:
            lua_pushlstring(L, (char *) "log", sizeof("log"));
            break;
        case NGX_HTTP_LUA_CONTEXT_HEADER_FILTER:
            lua_pushlstring(L, (char *) "header_filter", sizeof("header_filter"));
            break;
        case NGX_HTTP_LUA_CONTEXT_BODY_FILTER:
            lua_pushlstring(L, (char *) "body_filter", sizeof("body_filter"));
            break;
        
        default:
            luaL_error(L, "unknown phase: %d", ctx->context);
    }

    return 1;
}


void
ngx_http_lua_inject_phase_api(lua_State *L)
{
    lua_pushcfunction(L, ngx_http_lua_ngx_get_phase);
    lua_setfield(L, -2, "get_phase");
}

