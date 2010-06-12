#include "ngx_http_lua_util.h"
#include "ngx_http_lua_hook.h"

lua_State*
ngx_http_lua_newstate()
{
	lua_State *l = luaL_newstate();
	luaL_openlibs(l);

	return l;
}

ngx_int_t
ngx_http_lua_has_inline_var(ngx_str_t *s)
{
	return (ngx_http_script_variables_count(s) != 0);
}

char*
ngx_http_lua_rebase_path(ngx_pool_t *pool, ngx_str_t *str)
{
	char *path;
	u_char *tmp;

	if(str->data[0] != '/') {
		// make relative path based on NginX default prefix
		ndk_pallocpn_rn(path, pool, ngx_cycle->prefix.len + str->len + 1);
		tmp = ngx_cpymem(
				ngx_cpymem(path, ngx_cycle->prefix.data, ngx_cycle->prefix.len),
				str->data, str->len
				);
	} else {
		// copy absolute path directly
		ndk_pallocpn_rn(path, pool, str->len + 1);
		tmp = ngx_cpymem(path, str->data, str->len);
	}
	*tmp = '\0';

	return path;
}

#define NGX_LUA_CORT_REF "ngx_lua_cort_ref"

void init_ngx_lua_registry(lua_State *l)
{
	// ngx_lua_cort_ref = {}
	// 用于可靠系缚协程，强引用表
	// key = (ref)[int], val = (thread)
	lua_newtable(l);
	lua_setfield(l, LUA_REGISTRYINDEX, NGX_LUA_CORT_REF);
}

// vi:ts=4 sw=4 fdm=marker

