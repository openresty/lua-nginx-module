#ifndef DDEBUG
#define DDEBUG 0
#endif
#include "ddebug.h"

#include "ngx_http_lua_coroutine.h"


/*
 * Design:
 *
 * Info in Lua registry:
 * 1. A table stores 
 * Workflows:
 * 1. Create user coroutine
 *    When user code calls coroutine.create(...), control will be passed to the
 *    main thread (which manages all request-processing coroutines) by
 *    yielding. It will then call native coroutine library to create a new
 *    coroutine, inherits the parent coroutine's environment, and record the
 *    hierarchy in Lua registry. After that, control and the newly created
 *    coroutine will be passed back to the request processing coroutine by
 *    resuming.
 *
 * 2. Resume user coroutine
 *    When user code calls coroutine.resume(...) with a user coroutine, control
 *    will be passed to the main thread along with all arguments. It will then
 *    call native coroutine library to resume the execution of the given
 *    coroutine.
 *
 * 3. Yield user coroutine
 *    When user code calls coroutine.yield(...) in a user coroutine, control
 *    will be passed to the main thread. It will then look the parent coroutine
 *    up from Lua registry, and resume its execution.
 *
 * 4. User coroutine ends
 *    When user coroutine's execution ends normally/abnormally, control will be
 *    passed back to the main thread along with any return values. It will then
 *    look the parent coroutine up from Lua registry, and resume its execution
 *    with those return values.
 *
 * 5. Main thread ends
 *    When main thread ends normally/abnormally, ngx_lua will call
 *    ngx_http_lua_del_thread() to unanchor main thread from Lua registry so
 *    that it can be gc'd later. In this routine, we can look all user
 *    coroutines derived directly/indirectly from main thread up from Lua
 *    registry, and unanchor all of them. In this way, all user coroutines
 *    created by main thread will ends too.
 *
 * Decisions:
 * 1. How to represents user coroutine in Lua code?
 *    Method A: Represents user coroutine as-is, i.e. with a native thread
 *    value. The pros are that setfenv/getfenv/type works without further
 *    efforts. The cons are that we don't know when the coroutine is unref'd -
 *    because coroutine type don't have __gc metamethod, so we can't unanchor
 *    user coroutine but only do this job once when main thread ends. It maybe
 *    a problem if programs use lots of short-lived coroutines.
 *    
 *    Method B: Represents user coroutine using a userdata with __gc
 *    metamethod. The pros are that we can unanchor coroutine in __gc when the
 *    coroutine is unref'd. The cons are that setfenv/getfenv/type can't work
 *    without further wrapping.
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

	// TODO
	return luaL_error(L, "not implemented yet");
}


static int
ngx_http_lua_coroutine_resume(lua_State *L)
{
	// TODO
	return luaL_error(L, "not implemented yet");
}


static int
ngx_http_lua_coroutine_running(lua_State *L)
{
	// TODO
	return luaL_error(L, "not implemented yet");
}


static int
ngx_http_lua_coroutine_status(lua_State *L)
{
	// TODO
	return luaL_error(L, "not implemented yet");
}


static int
ngx_http_lua_coroutine_wrap(lua_State *L)
{
	// TODO
	return luaL_error(L, "not implemented yet");
}


static int
ngx_http_lua_coroutine_yield(lua_State *L)
{
	// TODO
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

