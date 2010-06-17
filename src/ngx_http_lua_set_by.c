/**
 * FIXME: needing change to the same mechanism used by content_by_lua directives
 * */
#include "ngx_http_lua_set_by.h"
#include "ngx_http_lua_hook.h"

static int
ngx_http_lua_param_get(lua_State *l)
{
	int idx = luaL_checkint(l, 2);
	int n = luaL_checkint(l, lua_upvalueindex(1));    // get number of args from closure
	ngx_http_variable_value_t *v = lua_touserdata(l, lua_upvalueindex(2));    // get args from closure

	if(idx < 0 || idx > n-1) {
		lua_pushnil(l);
	} else {
		lua_pushlstring(l, (const char*)(v[idx].data), v[idx].len);
	}

	return 1;
}

/**
 * Set environment table for the given code closure.
 *
 * Before:
 * 		| code closure | <- top
 * 		|      ...     |
 *
 * After:
 * 		| code closure | <- top
 * 		|      ...     |
 * */
static void
ngx_http_lua_set_by_lua_env(
		lua_State *l,
		ngx_http_request_t *r,
		size_t nargs,
		ngx_http_variable_value_t *args
		)
{
	// set NginX request pointer to current lua thread's globals table
	lua_pushlightuserdata(l, r);
	lua_setglobal(l, GLOBALS_SYMBOL_REQUEST);

	/**
	 * we want to create empty environment for current script
	 *
	 * setmetatable({}, {__index = _G})
	 *
	 * if a function or symbol is not defined in our env, __index will lookup
	 * in the global env.
	 *
	 * all variables created in the script-env will be thrown away at the end
	 * of the script run.
	 * */
	lua_newtable(l);    // new empty environment aka {}

	// override 'print' function
	lua_pushcfunction(l, ngx_http_lua_print);
	lua_setfield(l, -2, "print");

	// {{{ initialize ngx.* namespace
	lua_newtable(l);    // ngx.*

	lua_newtable(l);    // .arg table aka {}

	lua_newtable(l);    // the metatable for new param table
	lua_pushinteger(l, nargs);	// 1st upvalue: argument number
	lua_pushlightuserdata(l, args);	// 2nd upvalue: pointer to arguments
	lua_pushcclosure(l, ngx_http_lua_param_get, 2); // binding upvalues to __index meta-method closure
	lua_setfield(l, -2, "__index");
	lua_setmetatable(l, -2);    // tie the metatable to param table

	lua_setfield(l, -2, "arg");    // set ngx.arg table

	lua_setfield(l, -2, "ngx"); 
	// }}}

	// {{{ make new env inheriting main thread's globals table
	lua_newtable(l);    // the metatable for the new env
	lua_pushvalue(l, LUA_GLOBALSINDEX);
	lua_setfield(l, -2, "__index");
	lua_setmetatable(l, -2);    // setmetatable({}, {__index = _G})
	// }}}

	lua_setfenv(l, -2);    // set new running env for the code closure
}

ngx_int_t
ngx_http_lua_set_by_chunk(
		lua_State *l,
		ngx_http_request_t *r,
		ngx_str_t *val,
		ngx_http_variable_value_t *args,
		size_t nargs
		)
{
	size_t i;
	ngx_int_t rc;

	// set Lua VM panic handler
	lua_atpanic(l, ngx_http_lua_atpanic);

	// initialize nginx context in Lua VM, code chunk at stack top    sp = 1
	ngx_http_lua_set_by_lua_env(l, r, nargs, args);

	// passing directive arguments to the user code
	for(i = 0; i < nargs; ++i) {
		lua_pushlstring(l, (const char*)args[i].data, args[i].len);
	}

	// protected call user code
	rc = lua_pcall(l, nargs, 1, 0);
	if(rc) {
		// error occured when running loaded code
		const char *err_msg = lua_tostring(l, -1);
		ngx_log_error(NGX_LOG_ERR, r->connection->log, 0, "(lua-error) %s", err_msg);

		lua_settop(l, 0);	// clear remaining elems on stack
		assert(lua_gettop(l) == 0);

		return NGX_ERROR;
	}

	if(setjmp(ngx_http_lua_exception) == 0) {
		// try {
		size_t rlen;
		const char *rdata = lua_tolstring(l, -1, &rlen);

		if(rdata) {
			ndk_pallocpn(val->data, r->pool, rlen);
			if(!val->data) {
				ngx_log_error(NGX_LOG_ERR, r->connection->log, 0, "Failed to allocate result buffer!");

				return NGX_ERROR;
			}

			ngx_memcpy(val->data, rdata, rlen);
			val->len = rlen;
		} else {
			val->data = NULL;
			val->len = 0;
		}
	} else {
		// } catch
		dd("NginX execution restored");
	}

	// clear Lua stack
	lua_settop(l, 0);

	return NGX_OK;
}

