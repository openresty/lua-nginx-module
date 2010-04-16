#include "ngx_http_lua_directive.h"
#include "ngx_http_lua_util.h"

char*
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
	filter.func = cmd->post;
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

ngx_int_t
ngx_http_lua_filter_set_by_lua_inline(
		ngx_http_request_t *r,
		ngx_str_t *val,
		ngx_http_variable_value_t *v,
		void *data
		)
{
	lua_State *l;
	ngx_int_t rc;

	l = ngx_http_lua_newstate();

	// load Lua script												sp = 1
	rc = luaL_loadbuffer(l, (const char*)(v[0].data), v[0].len, "set_by_lua_inline");
	if(rc != 0) {
		// Oops! error occured when loading Lua script
		ngx_log_error(NGX_LOG_ERR, r->connection->log, 0,
				"Failed to load Lua script (rc = %d): %.*s", rc, v[0].len, v[0].data);

		lua_close(l);

		return NGX_ERROR;
	}

	// make sure we have a valid code chunk
	assert(lua_isfunction(l, -1));

	rc = ngx_http_lua_set_by_chunk(l, r, val, v, (size_t)data);

	lua_close(l);

	return rc;
}

ngx_int_t
ngx_http_lua_filter_set_by_lua_file(
		ngx_http_request_t *r,
		ngx_str_t *val,
		ngx_http_variable_value_t *v,
		void *data
		)
{
	lua_State *l;
	ngx_int_t rc;
	char *script_path;
	u_char *tmp;

	if(v[0].data[0] != '/') {
		// make relative path based on NginX default prefix
		ndk_pallocpn(script_path, r->pool, ngx_cycle->prefix.len+v[0].len+1);
		tmp = ngx_cpymem(
				ngx_cpymem(script_path, ngx_cycle->prefix.data, ngx_cycle->prefix.len),
				v[0].data, v[0].len
				);
	} else {
		// copy absolute path directly
		ndk_pallocpn(script_path, r->pool, v[0].len+1);
		tmp = ngx_cpymem(script_path, v[0].data, v[0].len);
	}
	*tmp = '\0';

	l = ngx_http_lua_newstate();

	// load Lua script from file
	rc = luaL_loadfile(l, script_path);
	if(rc != 0) {
		// Oops! error occured when loading Lua script
		ngx_log_error(NGX_LOG_ERR, r->connection->log, 0,
				"Failed to load Lua script (rc = %d): %.*s", rc, v[0].len, v[0].data);

		lua_close(l);

		return NGX_ERROR;
	}

	// make sure we have a valid code chunk
	assert(lua_isfunction(l, -1));

	rc = ngx_http_lua_set_by_chunk(l, r, val, v, (size_t)data);

	lua_close(l);

	return rc;
}

