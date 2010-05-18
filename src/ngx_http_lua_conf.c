#include "ngx_http_lua_conf.h"
#include "ngx_http_lua_util.h"

static void ngx_http_lua_cleanup_vm(void *data);
static char* ngx_http_lua_init_vm(ngx_conf_t *cf, ngx_http_lua_main_conf_t *lmcf);

void*
ngx_http_lua_create_main_conf(ngx_conf_t *cf)
{
	ngx_http_lua_main_conf_t *lmcf;

	ndk_pcallocp_rn(lmcf, cf->pool);
	dd("NginX Lua module main config structure initialized!");

	return lmcf;
}

char*
ngx_http_lua_init_main_conf(ngx_conf_t *cf, void *conf)
{
	ngx_http_lua_main_conf_t *lmcf = conf;

	if(lmcf->lua == NULL) {
		if(ngx_http_lua_init_vm(cf, lmcf) != NGX_CONF_OK) {
			ngx_conf_log_error(NGX_ERROR, cf, 0, "Failed to initialize Lua VM!");
			return NGX_CONF_ERROR;
		}

		dd("Lua VM initialized!");
	}

	return NGX_CONF_OK;
}

static void
ngx_http_lua_cleanup_vm(void *data)
{
	lua_State *lua = data;

	if(lua != NULL) {
		lua_close(lua);

		dd("Lua VM closed!");
	}
}

static char*
ngx_http_lua_init_vm(ngx_conf_t *cf, ngx_http_lua_main_conf_t *lmcf)
{
	ngx_pool_cleanup_t *cln;

	// add new cleanup handler to config mem pool
	cln = ngx_pool_cleanup_add(cf->pool, 0);
	if(cln == NULL) {
		return NGX_CONF_ERROR;
	}

	// create new Lua VM instance
	lmcf->lua = ngx_http_lua_newstate();
	if(lmcf->lua == NULL) {
		return NGX_CONF_ERROR;
	}

	// register cleanup handler for Lua VM
	cln->handler = ngx_http_lua_cleanup_vm;
	cln->data = lmcf->lua;

	return NGX_CONF_OK;
}

