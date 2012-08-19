#ifndef DDEBUG
#define DDEBUG 0
#endif
#include "ddebug.h"


#include "ngx_http_lua_coroutine.h"
#include "ngx_http_lua_util.h"
#include "ngx_http_lua_probe.h"


/*
 * Design:
 *
 * In order to support using ngx.* API in Lua coroutines, we have to create
 * new coroutine in the main coroutine instead of the calling coroutine
 */


static int ngx_http_lua_coroutine_create(lua_State *L);
static int ngx_http_lua_coroutine_resume(lua_State *L);
static int ngx_http_lua_coroutine_yield(lua_State *L);


static char ngx_http_lua_orig_co_status_key;


static int
ngx_http_lua_coroutine_create(lua_State *L)
{
    lua_State                     *mt;  /* the main thread */
    lua_State                     *co;  /* new coroutine to be created */
    ngx_http_request_t            *r;
    ngx_http_lua_main_conf_t      *lmcf;
    ngx_http_lua_ctx_t            *ctx;

    /* L is the current thread */

    luaL_argcheck(L, lua_isfunction(L, 1) && !lua_iscfunction(L, 1), 1,
                 "Lua function expected");

    lua_pushlightuserdata(L, &ngx_http_lua_request_key);
    lua_rawget(L, LUA_GLOBALSINDEX);
    r = lua_touserdata(L, -1);
    lua_pop(L, 1);

    if (r == NULL) {
        return luaL_error(L, "no request found");
    }

    ctx = ngx_http_get_module_ctx(r, ngx_http_lua_module);
    if (ctx == NULL) {
        return luaL_error(L, "no request ctx found");
    }

    ngx_http_lua_check_context(L, ctx, NGX_HTTP_LUA_CONTEXT_REWRITE
                               | NGX_HTTP_LUA_CONTEXT_ACCESS
                               | NGX_HTTP_LUA_CONTEXT_CONTENT);

    lmcf = ngx_http_get_module_main_conf(r, ngx_http_lua_module);
    mt = lmcf->lua;

    /* create new coroutine on root Lua state, so it always yields
     * to main Lua thread
     */
    co = lua_newthread(mt);

    ngx_http_lua_probe_user_coroutine_create(r, L, co);

    /* make new coroutine share globals of the parent coroutine.
     * NOTE: globals don't have to be separated! */
    lua_pushvalue(L, LUA_GLOBALSINDEX);
    lua_xmove(L, co, 1);
    lua_replace(co, LUA_GLOBALSINDEX);

    lua_xmove(mt, L, 1);    /* move coroutine from main thread to L */

    lua_pushvalue(L, 1);    /* copy entry function to top of L*/
    lua_xmove(L, co, 1);    /* move entry function from L to co */

    return 1;    /* return new coroutine to Lua */
}


static int
ngx_http_lua_coroutine_resume(lua_State *L)
{
    ngx_str_t                    status = ngx_null_string;
    lua_State                   *co, *mt;
    ngx_http_request_t          *r;
    ngx_http_lua_ctx_t          *ctx;
    ngx_http_lua_main_conf_t    *lmcf;

    co = lua_tothread(L, 1);

    luaL_argcheck(L, co, 1, "coroutine expected");

    lua_pushlightuserdata(L, &ngx_http_lua_request_key);
    lua_rawget(L, LUA_GLOBALSINDEX);
    r = lua_touserdata(L, -1);
    lua_pop(L, 1);

    if (r == NULL) {
        return luaL_error(L, "no request found");
    }

    ctx = ngx_http_get_module_ctx(r, ngx_http_lua_module);
    if (ctx == NULL) {
        return luaL_error(L, "no request ctx found");
    }

    ngx_http_lua_check_context(L, ctx, NGX_HTTP_LUA_CONTEXT_REWRITE
                               | NGX_HTTP_LUA_CONTEXT_ACCESS
                               | NGX_HTTP_LUA_CONTEXT_CONTENT);

    lua_pushlightuserdata(L, &ngx_http_lua_orig_co_status_key);
    lua_rawget(L, LUA_REGISTRYINDEX);
    lua_pushvalue(L, 1);
    lua_call(L, 1, 1);

    status.data = (u_char *) lua_tolstring(L, -1, &status.len);

    dd("co status: %s", status.data);

    /* TODO we should reject resuming logically "normal" coroutines here
     * as well */

    if (status.len != sizeof("suspended") - 1) {
        lua_pushboolean(L, 0);
        lua_pushfstring(L, "cannot resume %s coroutine",
                        status.data ? (char *) status.data : "unknown");
        return 2;
    }

    lua_pop(L, 1); /* remove the status string */

    ngx_http_lua_probe_user_coroutine_resume(r, L, co);

    lmcf = ngx_http_get_module_main_conf(r, ngx_http_lua_module);
    mt = lmcf->lua;

    /* record parent-child relationship */

    ngx_http_lua_get_coroutine_parents(mt);

    lua_pushthread(co); /* key: child coroutine */
    lua_xmove(co, mt, 1);
    lua_pushthread(L); /* val: parent coroutine */
    lua_xmove(L, mt, 1);
    lua_rawset(mt, -3);
    lua_pop(mt, 1);

    ctx->co_op = NGX_HTTP_LUA_USER_CORO_RESUME;

    /* yield and pass args to main thread, and resume target coroutine from
     * there */
    return lua_yield(L, lua_gettop(L));
}


static int
ngx_http_lua_coroutine_yield(lua_State *L)
{
    ngx_http_request_t          *r;
    ngx_http_lua_ctx_t          *ctx;

    lua_pushlightuserdata(L, &ngx_http_lua_request_key);
    lua_rawget(L, LUA_GLOBALSINDEX);
    r = lua_touserdata(L, -1);
    lua_pop(L, 1);

    if (r == NULL) {
        return luaL_error(L, "no request found");
    }

    ctx = ngx_http_get_module_ctx(r, ngx_http_lua_module);
    if (ctx == NULL) {
        return luaL_error(L, "no request ctx found");
    }

    ngx_http_lua_check_context(L, ctx, NGX_HTTP_LUA_CONTEXT_REWRITE
                               | NGX_HTTP_LUA_CONTEXT_ACCESS
                               | NGX_HTTP_LUA_CONTEXT_CONTENT);

    ctx->co_op = NGX_HTTP_LUA_USER_CORO_YIELD;

    /* yield and pass retvals to main thread,
     * and resume parent coroutine there */
    return lua_yield(L, lua_gettop(L));
}


void
ngx_http_lua_inject_coroutine_api(ngx_log_t *log, lua_State *L)
{
    int         rc;

    /* new coroutine table */
    lua_newtable(L);

    /* get old coroutine table */
    lua_getglobal(L, "coroutine");

    /* set running to the old one */
    lua_getfield(L, -1, "running");
    lua_setfield(L, -3, "running");

    /* set status to the old one */
    lua_getfield(L, -1, "status");
    lua_setfield(L, -3, "status");

    /* save coroutine.status to registry */
    lua_pushlightuserdata(L, &ngx_http_lua_orig_co_status_key);
    lua_getfield(L, -2, "status");
    lua_rawset(L, LUA_REGISTRYINDEX);

    /* pop the old coroutine */
    lua_pop(L, 1);

    lua_pushcfunction(L, ngx_http_lua_coroutine_create);
    lua_setfield(L, -2, "create");
    lua_pushcfunction(L, ngx_http_lua_coroutine_resume);
    lua_setfield(L, -2, "resume");
    lua_pushcfunction(L, ngx_http_lua_coroutine_yield);
    lua_setfield(L, -2, "yield");

    lua_setglobal(L, "coroutine");

    /* inject wrap */
    {
        const char buf[] =
            "local create, resume = coroutine.create, coroutine.resume\n"
            "coroutine.wrap = function(f)\n"
               "local co = create(f)\n"
               "return function(...) return select(2, resume(co, ...)) end\n"
            "end";

        rc = luaL_loadbuffer(L, buf, sizeof(buf) - 1, "coroutine.wrap");
    }

    if (rc != 0) {
        ngx_log_error(NGX_LOG_ERR, log, 0,
                      "failed to load Lua code for coroutine.wrap(): %i: %s",
                      rc, lua_tostring(L, -1));

        lua_pop(L, 1);
        return;
    }

    rc = lua_pcall(L, 0, 0, 0);
    if (rc != 0) {
        ngx_log_error(NGX_LOG_ERR, log, 0,
                      "failed to run the Lua code for coroutine.wrap(): %i: %s",
                      rc, lua_tostring(L, -1));
        lua_pop(L, 1);
    }
}

