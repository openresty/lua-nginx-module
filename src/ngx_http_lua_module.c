#define DDEBUG 1
#include "ddebug.h"
#include <ndk.h>
#include <lua.h>
#include <lualib.h>
#include <lauxlib.h>
#include <assert.h>
#include <setjmp.h>

static ngx_int_t ngx_http_lua_filter_set_by_lua(
		ngx_http_request_t *r,
		ngx_str_t *val,
		ngx_http_variable_value_t *v,
		void *data
		);
static char* ngx_http_lua_set_by_lua(
		ngx_conf_t *cf,
		ngx_command_t *cmd,
		void *conf
		);

static ngx_command_t ngx_http_lua_cmds[] = {
	/* set_by_lua $res <script> [$arg1 [$arg2 [...]]] */
	{
		ngx_string("set_by_lua"),
		NGX_HTTP_MAIN_CONF | NGX_HTTP_SRV_CONF | NGX_HTTP_SIF_CONF |
		NGX_HTTP_LOC_CONF | NGX_HTTP_LIF_CONF | NGX_CONF_2MORE,
		ngx_http_lua_set_by_lua,
		0,
		0,
		NULL
	},

	ngx_null_command
};

ngx_http_module_t ngx_http_lua_module_ctx = {
	NULL,	// preconfiguration
	NULL,	// postconfiguration

	NULL,	// create main configuration
	NULL,	// init main configuration

	NULL,	// create server configuration
	NULL,	// merge server configuration

	NULL,	// create location configuration
	NULL	// merge location configuration
};

ngx_module_t ngx_http_lua_module = {
	NGX_MODULE_V1,
	&ngx_http_lua_module_ctx,	// module context
	ngx_http_lua_cmds,			// module directives
	NGX_HTTP_MODULE,			// module type
	NULL,						// init master
	NULL,						// init module
	NULL,						// init process
	NULL,						// init thread
	NULL,						// exit thread
	NULL,						// exit process
	NULL,						// exit master
	NGX_MODULE_V1_PADDING
};

// longjmp mark for restoring nginx execution after Lua VM crashing
static jmp_buf exceptionjmp;

static int ngx_http_lua_atpanic(lua_State *l)
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
	longjmp(exceptionjmp, 1);
}

static int ngx_http_lua_print(lua_State *l)
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

static int ngx_http_lua_param_get(lua_State *l)
{
	int idx = luaL_checkint(l, 2);
	int n = luaL_checkint(l, lua_upvalueindex(1));
	ngx_http_variable_value_t *v = lua_touserdata(l, lua_upvalueindex(2));

	if(idx < 0 || idx > n-1) {
		lua_pushnil(l);
	} else {
		lua_pushlstring(l, (const char*)(v[idx].data), v[idx].len);
	}

	return 1;
}

static ngx_int_t
ngx_http_lua_filter_set_by_lua(
		ngx_http_request_t *r,
		ngx_str_t *val,
		ngx_http_variable_value_t *v,
		void *data
		)
{
	lua_State *l;
	int rc;

	l = luaL_newstate();
	luaL_openlibs(l);

	// load Lua script												sp = 1
	rc = luaL_loadbuffer(l, (const char*)(v[0].data), v[0].len, "set_by_lua script");
	if(rc != 0) {
		// Oops! error occured when loading Lua script
		ngx_log_error(NGX_LOG_ERR, r->connection->log, 0,
				"Failed to load Lua script (rc = %d): %.*s", rc, v[0].len, v[0].data);

		lua_close(l);

		return NGX_ERROR;
	}

	// make sure we have a valid code chunk
	assert(lua_isfunction(l, -1));

	// set Lua VM panic handler
	lua_atpanic(l, ngx_http_lua_atpanic);

	// initialize nginx context in Lua VM
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

	lua_newtable(l);	// .param table aka {}						sp = 4
	lua_newtable(l);	// the metatable for new param table		sp = 5
	lua_pushinteger(l, (size_t)data);	//							sp = 6
	lua_pushlightuserdata(l, v);	//								sp = 7
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

	rc = lua_pcall(l, 0, 1, 0);
	if(rc) {
		// error occured when running loaded code
		const char *err_msg = lua_tostring(l, -1);
		ngx_log_error(NGX_LOG_ERR, r->connection->log, 0, "(lua-error) %s", err_msg);

		lua_pop(l, 1);
		assert(lua_gettop(l) == 0);

		lua_close(l);
		return NGX_ERROR;
	}

	{
		size_t rlen;
		const char *rdata = lua_tolstring(l, -1, &rlen);

		if(rdata) {
			ndk_pallocpn(val->data, r->pool, rlen);
			if(!val->data) {
				ngx_log_error(NGX_LOG_ERR, r->connection->log, 0, "Failed to allocate result buffer!");
				lua_close(l);
				return NGX_ERROR;
			}
			ngx_memcpy(val->data, rdata, rlen);
			val->len = rlen;
		} else {
			val->data = NULL;
			val->len = 0;
		}
	}

	lua_close(l);

#if 0
	{
		size_t i, n = (size_t)data;
		for(i = 0; i < n; ++i) {
			dd("set_by_lua: param[%d] = '%.*s'", i, v[i].len, v[i].data);
		}
	}
#endif

	return NGX_OK;
}

static char*
ngx_http_lua_set_by_lua(
		ngx_conf_t *cf,
		ngx_command_t *cmd,
		void *conf
		)
{
	ngx_str_t *args;
	ngx_str_t target;
	ndk_set_var_t filter;

	/*
	 * args[0] = "set_by_lua"
	 * args[1] = target variable name
	 * args[2] = lua script to be executed
	 * args[3..] = real params
	 * */
	args = cf->args->elts;
	target = args[1];

	filter.type = NDK_SET_VAR_MULTI_VALUE_DATA;
	filter.func = ngx_http_lua_filter_set_by_lua;
	filter.size = cf->args->nelts - 2;	// get number of real params + 1 (lua script)
	filter.data = (void*)filter.size;

#if 0
	dd("set_by_lua: target = '%.*s', script = '%.*s', nargs = %d",
			target.len, target.data,
			args[2].len, args[2].data,
			filter.size);
#endif
	return ndk_set_var_multi_value_core(cf, &target, &args[2], &filter);
}

