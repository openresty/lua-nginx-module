#ifndef DDEBUG
#define DDEBUG 0
#endif
#include "ddebug.h"


#include "ngx_http_lua_uthread.h"
#include "ngx_http_lua_coroutine.h"
#include "ngx_http_lua_util.h"
#include "ngx_http_lua_probe.h"


static int ngx_http_lua_uthread_create(lua_State *L);


void
ngx_http_lua_inject_uthread_api(ngx_log_t *log, lua_State *L)
{
    /* new thread table */
    lua_newtable(L);

    lua_pushcfunction(L, ngx_http_lua_uthread_create);
    lua_setfield(L, -2, "create");

    lua_setfield(L, -2, "thread");
}


static int
ngx_http_lua_uthread_create(lua_State *L)
{
    ngx_http_request_t           *r;
    ngx_http_lua_ctx_t           *ctx;
    ngx_http_lua_co_ctx_t        *coctx = NULL;

    ngx_http_lua_coroutine_create_helper(L, &r, &ctx, &coctx);

    /* anchor the newly created coroutine into the Lua registry */

    lua_pushlightuserdata(L, &ngx_http_lua_coroutines_key);
    lua_rawget(L, LUA_REGISTRYINDEX);
    lua_pushvalue(L, -3);
    coctx->co_ref = luaL_ref(L, -2);
    lua_pop(L, 1);

    ctx->uthreads++;

    coctx->co_status = NGX_HTTP_LUA_CO_RUNNING;
    ctx->co_op = NGX_HTTP_LUA_USER_THREAD_RESUME;

    if (ngx_http_lua_post_thread(r, ctx, ctx->cur_co_ctx) != NGX_OK) {
        return luaL_error(L, "out of memory");
    }

    ctx->cur_co_ctx = coctx;

    ngx_http_lua_probe_user_thread_create(r, L, coctx->co);

    return lua_yield(L, 0);
}

