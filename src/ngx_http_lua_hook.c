#include "ngx_http_lua_hook.h"

/**
 * Override default Lua panic handler, output VM crash reason to NginX error
 * log, and restore execution to the nearest jmp-mark.
 * 
 * @param l Lua state pointer
 * @retval Long jump to the nearest jmp-mark, never returns.
 * @note NginX request pointer should be stored in Lua VM registry with key
 * 'ngx._req' in order to make logging working.
 * */
int
ngx_http_lua_atpanic(lua_State *l)
{
	const char *s = luaL_checkstring(l, 1);
	ngx_http_request_t *r;

	lua_pushstring(l, "ngx._req");
	lua_gettable(l, LUA_REGISTRYINDEX);
	r = lua_touserdata(l, -1);
	lua_pop(l, 1);

	// log Lua VM crashing reason to error log
	if(r && r->connection && r->connection->log) {
		ngx_log_error(NGX_LOG_ERR, r->connection->log, 0, "(lua-atpanic) Lua VM crashed, reason: %s", s);
	} else {
		dd("(lua-atpanic) can't output Lua VM crashing reason to error log"
				" due to invalid logging context: %s", s);
	}

	// restore nginx execution
	longjmp(ngx_http_lua_exception, 1);
}

/**
 * Override Lua print function, output message to NginX error logs.
 *
 * @param l Lua state pointer
 * @retval always 0 (don't return values to Lua)
 * @note NginX request pointer should be stored in Lua VM registry with key
 * 'ngx._req' in order to make logging working.
 * */
int
ngx_http_lua_print(lua_State *l)
{
	const char *s = luaL_checkstring(l, 1);
	ngx_http_request_t *r;

	lua_pushstring(l, "ngx._req");
	lua_gettable(l, LUA_REGISTRYINDEX);
	r = lua_touserdata(l, -1);
	lua_pop(l, 1);

	if(r && r->connection && r->connection->log) {
		ngx_log_error(NGX_LOG_ERR, r->connection->log, 0, "(lua-print) %s", s);
	} else {
		dd("(lua-print) can't output print content to error log"
				" due to invalid logging context: %s", s);
	}

	return 0;
}

