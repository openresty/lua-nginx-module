#include "ngx_http_lua_util.h"
#include "ngx_http_lua_hook.h"

// longjmp mark for restoring nginx execution after Lua VM crashing
jmp_buf ngx_http_lua_exception;

static int ngx_http_lua_param_get(lua_State *l)
{
	int idx = luaL_checkint(l, 2);
	int n = luaL_checkint(l, lua_upvalueindex(1));	// get number of args from closure
	ngx_http_variable_value_t *v = lua_touserdata(l, lua_upvalueindex(2));	// get args from closure

	if(idx < 0 || idx > n-1) {
		lua_pushnil(l);
	} else {
		lua_pushlstring(l, (const char*)(v[idx].data), v[idx].len);
	}

	return 1;
}

lua_State*
ngx_http_lua_newstate()
{
	lua_State *l = luaL_newstate();
	luaL_openlibs(l);
	
	return l;
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
	ngx_int_t rc;

	// set Lua VM panic handler
	lua_atpanic(l, ngx_http_lua_atpanic);

	// initialize nginx context in Lua VM, code chunk at stack top	sp = 1
	lua_pushstring(l, "ngx._req");						//			sp = 2
	lua_pushlightuserdata(l, r);						//			sp = 3
	lua_settable(l, LUA_REGISTRYINDEX);					//			sp = 1

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
	lua_newtable(l);	// new empty environment aka {}				sp = 2

	// override Lua VM built-in print function
	lua_pushcfunction(l, ngx_http_lua_print);			//			sp = 3
	lua_setfield(l, -2, "print");	// -1 is the env we want to set	sp = 2

	lua_newtable(l);	// {}										sp = 3

	lua_newtable(l);	// .arg table aka {}						sp = 4
	lua_newtable(l);	// the metatable for new param table		sp = 5
	lua_pushinteger(l, nargs);	//									sp = 6
	lua_pushlightuserdata(l, args);	//								sp = 7
	lua_pushcclosure(l, ngx_http_lua_param_get, 2);		//			sp = 6
	lua_setfield(l, -2, "__index");						//			sp = 5
	lua_setmetatable(l, -2);	// tie the metatable to param table	sp = 4
	lua_setfield(l, -2, "arg");	// set ngx.arg table				sp = 3

	lua_setfield(l, -2, "ngx");	// ngx.*							sp = 2

	lua_newtable(l);	// the metatable for the new env			sp = 3
	lua_pushvalue(l, LUA_GLOBALSINDEX);					//			sp = 4
	lua_setfield(l, -2, "__index");						//			sp = 3
	lua_setmetatable(l, -2);	// setmetatable({}, {__index = _G})	sp = 2

	lua_setfenv(l, -2);	// set new running env for the loaded code	sp = 1

#ifdef NGX_HTTP_LUA_USE_ELLIPSIS
	{
		size_t i;
		for(i = 0; i < nargs; ++i) {
			lua_pushlstring(l, (const char*)args[i].data, args[i].len);
		}
		rc = lua_pcall(l, nargs, 1, 0);
	}
#else
	rc = lua_pcall(l, 0, 1, 0);
#endif
	if(rc) {
		// error occured when running loaded code
		const char *err_msg = lua_tostring(l, -1);
		ngx_log_error(NGX_LOG_ERR, r->connection->log, 0, "(lua-error) %s", err_msg);

		lua_pop(l, 1);
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

	return NGX_OK;
}

