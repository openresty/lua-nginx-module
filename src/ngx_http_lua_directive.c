#include "ngx_http_lua_directive.h"
#include "ngx_http_lua_util.h"
#include "ngx_http_lua_cache.h"
#include "ngx_http_lua_conf.h"
#include "ngx_http_lua_content.h"

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

	// prevent variable appearing in Lua inline script/file path
	if(ngx_http_lua_has_inline_var(&args[2])) {
		ngx_conf_log_error(NGX_LOG_ERR, cf, 0,
				"Lua inline script or file path should not has inline variable: %V",
				&args[2]);
		return NGX_CONF_ERROR;
	}

	filter.type = NDK_SET_VAR_MULTI_VALUE_DATA;
	filter.func = cmd->post;
	filter.size = cf->args->nelts - 2;    // get number of real params + 1 (lua script)
	filter.data = (void*)filter.size;

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
	ngx_http_lua_main_conf_t *lmcf;
    const char *err;

	lmcf = ngx_http_get_module_main_conf(r, ngx_http_lua_module);
	l = lmcf->lua;

	// load Lua inline script (w/ cache)        sp = 1
	rc = ngx_http_lua_cache_loadbuffer(l, (const char*)(v[0].data), v[0].len, "set_by_lua_inline");

	if(rc != NGX_OK) {
		// Oops! error occured when loading Lua script
        if (rc == LUA_ERRMEM) {
            err = "memory allocation error";
        } else {
            if (lua_isstring(l, -1)) {
                err = lua_tostring(l, -1);
            } else {
                err = "syntax error";
            }
        }

		ngx_log_error(NGX_LOG_ERR, r->connection->log, 0,
				"Failed to load Lua script chunk (rc = %d): %s %v", rc, err, &v[0]);

		return NGX_ERROR;
	}

	// make sure we have a valid code chunk
	assert(lua_isfunction(l, -1));

	rc = ngx_http_lua_set_by_chunk(l, r, val, v, (size_t)data);

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
	lua_State                   *l;
	ngx_int_t                    rc;
	char                        *script_path;
	ngx_http_lua_main_conf_t    *lmcf;
	ngx_str_t                    tmp;
    const char                  *err;

	tmp.data = v[0].data;
	tmp.len = v[0].len;

	script_path = ngx_http_lua_rebase_path(r->pool, &tmp);
	if (script_path == NULL) {
		ngx_log_error(NGX_LOG_ERR, r->connection->log, 0,
				"Failed to allocate memory to store absolute path: raw path='%v'",
				&v[0]);

        return NGX_ERROR;
	}

	lmcf = ngx_http_get_module_main_conf(r, ngx_http_lua_module);
	l = lmcf->lua;

	// load Lua script file (w/ cache)		sp = 1
	rc = ngx_http_lua_cache_loadfile(l, script_path);

	if (rc != NGX_OK) {
		// Oops! error occured when loading Lua script
        if (rc == LUA_ERRMEM) {
            err = "memory allocation error";

        } else {
            if (lua_isstring(l, -1)) {
                err = lua_tostring(l, -1);

            } else {
                err = "syntax error";
            }
        }

		ngx_log_error(NGX_LOG_ERR, r->connection->log, 0,
				"Failed to load Lua script file (rc = %d): %s: %s", rc, err, script_path);

		return NGX_ERROR;
	}

	// make sure we have a valid code chunk
	assert(lua_isfunction(l, -1));

	rc = ngx_http_lua_set_by_chunk(l, r, val, v, (size_t)data);

	return rc;
}

char *
ngx_http_lua_content_by_lua(
		ngx_conf_t *cf,
		ngx_command_t *cmd,
		void *conf
		)
{
	ngx_str_t *args;
	ngx_http_core_loc_conf_t *clcf;
	ngx_http_lua_loc_conf_t *llcf = conf;

	// must specifiy a content handler
	if(cmd->post == NULL) {
		return NGX_CONF_ERROR;
	}

	// update lua script data
	/*
	 * args[0] = "content_by_lua"
	 * args[1] = lua script to be executed
	 * */
	args = cf->args->elts;
	// prevent variable appearing in Lua inline script/file path
	if(ngx_http_lua_has_inline_var(&args[1])) {
		ngx_conf_log_error(NGX_LOG_ERR, cf, 0,
				"Lua inline script or file path should not has inline variable: %V",
				&args[1]);
		return NGX_CONF_ERROR;
	}
	if(args[1].len == 0) {
		// Oops...Invalid location conf
		ngx_conf_log_error(NGX_LOG_ERR, cf, 0,
				"Invalid location config: no runnable Lua code");
		return NGX_CONF_ERROR;
	}
	llcf->src = args[1];

	// register location content handler
	clcf = ngx_http_conf_get_module_loc_conf(cf, ngx_http_core_module);
	if(clcf == NULL) {
		return NGX_CONF_ERROR;
	}
	clcf->handler = cmd->post;

	return NGX_CONF_OK;
}

ngx_int_t
ngx_http_lua_content_handler_inline(ngx_http_request_t *r)
{
	lua_State *l;
	ngx_int_t rc;
	ngx_http_lua_main_conf_t *lmcf;
	ngx_http_lua_loc_conf_t *llcf;

	llcf = ngx_http_get_module_loc_conf(r, ngx_http_lua_module);
	lmcf = ngx_http_get_module_main_conf(r, ngx_http_lua_module);
	l = lmcf->lua;

	// load Lua inline script (w/ cache)        sp = 1
	rc = ngx_http_lua_cache_loadbuffer(l, (const char*)(llcf->src.data), llcf->src.len, "set_by_lua_inline");
	if(rc != NGX_OK) {
		// Oops...Error occured when loading Lua script
		ngx_log_error(NGX_LOG_ERR, r->connection->log, 0,
				"Failed to load Lua script chunk (rc = %d): %v", rc, &(llcf->src));

		return NGX_ERROR;
	}

	// make sure we have a valid code chunk
	assert(lua_isfunction(l, -1));

	rc = ngx_http_lua_content_by_chunk(l, r);

	return rc;
}

ngx_int_t
ngx_http_lua_content_handler_file(ngx_http_request_t *r)
{
	lua_State *l;
	ngx_int_t rc;
	char *script_path;
	ngx_http_lua_main_conf_t *lmcf;
	ngx_http_lua_loc_conf_t *llcf;
	ngx_str_t tmp;

	llcf = ngx_http_get_module_loc_conf(r, ngx_http_lua_module);

	tmp.data = llcf->src.data;
	tmp.len = llcf->src.len;

	script_path = ngx_http_lua_rebase_path(r->pool, &tmp);
	if(script_path == NULL) {
		ngx_log_error(NGX_LOG_ERR, r->connection->log, 0,
				"Failed to allocate memory to store absolute path: raw path='%v'",
				&(llcf->src));
		return NGX_ERROR;
	}

	lmcf = ngx_http_get_module_main_conf(r, ngx_http_lua_module);
	l = lmcf->lua;

	// load Lua script file (w/ cache)		sp = 1
	rc = ngx_http_lua_cache_loadfile(l, script_path);
	if(rc != NGX_OK) {
		// Oops! error occured when loading Lua script
		ngx_log_error(NGX_LOG_ERR, r->connection->log, 0,
				"Failed to load Lua script file (rc = %d): %s", rc, script_path);

		return NGX_ERROR;
	}

	// make sure we have a valid code chunk
	assert(lua_isfunction(l, -1));

	rc = ngx_http_lua_content_by_chunk(l, r);

	return rc;
}

// vi:ts=4 sw=4 fdm=marker

