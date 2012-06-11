#ifndef DDEBUG
#define DDEBUG 0
#endif
#include "ddebug.h"

#include "nginx.h"
#include "ngx_http_lua_coroutine.h"
#include "ngx_http_lua_api.h"


/*
 * Design:
 *
 * In order to support using ngx.* API in Lua coroutines, we have to create
 * new coroutine in the main coroutine instead of the calling coroutine
 */

static int ngx_http_lua_coroutine_create(lua_State *L);
static int ngx_http_lua_coroutine_resume(lua_State *L);
static int ngx_http_lua_coroutine_running(lua_State *L);
static int ngx_http_lua_coroutine_status(lua_State *L);
static int ngx_http_lua_coroutine_wrap(lua_State *L);
static int ngx_http_lua_coroutine_yield(lua_State *L);


static int
ngx_http_lua_coroutine_create(lua_State *L)
{
	lua_State 					*cr;
	lua_State 					*ml;
	ngx_http_request_t 			*r;
	ngx_http_lua_main_conf_t	*lmcf;

	luaL_argcheck(L, lua_isfunction(L, 1) && !lua_iscfunction(L, 1), 1,
			"Lua function expected");

	r = ngx_http_lua_get_request(L);
	lmcf = ngx_http_get_module_main_conf(r, ngx_http_lua_module);
	ml = lmcf->lua;

	/* create new coroutine on main thread, so it always yield to main thread
	 */
	cr = lua_newthread(ml);

	/* make new coroutine share globals of the parent coroutine.
	 * NOTE: globals don't have to be separated! */
	lua_pushvalue(L, LUA_GLOBALSINDEX);
	lua_xmove(L, cr, 1);
	lua_replace(cr, LUA_GLOBALSINDEX);

	lua_xmove(ml, L, 1);	/* move coroutine from main L to L */

	lua_pushvalue(L, 1);	/* copy entry function to top of L*/
	lua_xmove(L, cr, 1);	/* move entry function from L to cr */

	/* record parent-child relationship */
	lua_getfield(ml, LUA_REGISTRYINDEX, NGX_LUA_CORT_REL);
	lua_pushthread(cr); /* key: child coroutine */
	lua_xmove(cr, ml, 1);
	lua_pushthread(L); /* val: parent coroutine */
	lua_xmove(L, ml, 1);
	lua_settable(ml, -3);
	lua_pop(ml, 1);

	return 1;	/* return new coroutine to Lua */
}


static int
ngx_http_lua_coroutine_resume(lua_State *L)
{
	ngx_http_request_t *r;
	ngx_http_lua_ctx_t *ctx;

	luaL_argcheck(L, lua_isthread(L, 1), 1, "Lua coroutine expected");

	r = ngx_http_lua_get_request(L);
	ctx = ngx_http_get_module_ctx(r, ngx_http_lua_module);
	if (ctx == NULL) {
		return luaL_error(L, "no request ctx found");
	}

	ctx->cc_op = RESUME;

	/* yield and pass args to main L, and resume target coroutine from there
	 */
	return lua_yield(L, lua_gettop(L));
}


static int
ngx_http_lua_coroutine_yield(lua_State *L)
{
	ngx_http_request_t *r;
	ngx_http_lua_ctx_t *ctx;

	r = ngx_http_lua_get_request(L);
	ctx = ngx_http_get_module_ctx(r, ngx_http_lua_module);
	if (ctx == NULL) {
		return luaL_error(L, "no request ctx found");
	}

	ctx->cc_op = YIELD;

	/* yield and pass retvals to main L, and resume parent coroutine there */
	return lua_yield(L, lua_gettop(L));
}


static int
ngx_http_lua_coroutine_running(lua_State *L)
{
	// TODO p2
	return luaL_error(L, "not implemented yet");
}


static int
ngx_http_lua_coroutine_status(lua_State *L)
{
	// TODO p2
	return luaL_error(L, "not implemented yet");
}


static int
ngx_http_lua_coroutine_wrap(lua_State *L)
{
	// TODO p1
	return luaL_error(L, "not implemented yet");
}


void
ngx_http_lua_inject_coroutine_api(lua_State *L)
{
	lua_newtable(L);	/* coroutine.* */
	
	lua_pushcfunction(L, ngx_http_lua_coroutine_create);
	lua_setfield(L, -2, "create");
	lua_pushcfunction(L, ngx_http_lua_coroutine_resume);
	lua_setfield(L, -2, "resume");
	lua_pushcfunction(L, ngx_http_lua_coroutine_running);
	lua_setfield(L, -2, "running");
	lua_pushcfunction(L, ngx_http_lua_coroutine_status);
	lua_setfield(L, -2, "status");
	lua_pushcfunction(L, ngx_http_lua_coroutine_wrap);
	lua_setfield(L, -2, "wrap");
	lua_pushcfunction(L, ngx_http_lua_coroutine_yield);
	lua_setfield(L, -2, "yield");

	lua_setglobal(L, "coroutine");
}

