#include <ndk.h>
#include <lua.h>
#include "ddebug.h"

static ngx_int_t ngx_http_set_var_by_lua(
		ngx_http_request_t *r,
		ngx_str_t *val,
		ngx_http_variable_value_t *v
		);

static ndk_set_var_t ngx_http_var_set_by_lua = {
	NDK_SET_VAR_MULTI_VALUE,
	ngx_http_set_var_by_lua,
	2,
	NULL
};

static ngx_command_t ngx_http_lua_cmds[] = {
	/* set_by_lua $res <script> [$arg1 [$arg2 [...]]] */
	{
		ngx_string("set_by_lua"),
		NGX_HTTP_MAIN_CONF | NGX_HTTP_SRV_CONF | NGX_HTTP_SIF_CONF |
		NGX_HTTP_LOC_CONF | NGX_HTTP_LIF_CONF | NGX_CONF_2MORE,
		ndk_set_var_multi_value,
		0,
		0,
		&ngx_http_var_set_by_lua
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

/*
 * */
static ngx_int_t
ngx_http_set_var_by_lua(
		ngx_http_request_t *r,
		ngx_str_t *val,
		ngx_http_variable_value_t *v
		)
{
	dd("*** ngx_http_set_var_by_lua() called");
#define NOT_IMPL_YET "(sorry, not implemented yet)"
	val->data = (u_char*)NOT_IMPL_YET;
	val->len = sizeof(NOT_IMPL_YET)-1;

	return NGX_OK;
}

