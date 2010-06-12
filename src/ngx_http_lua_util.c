#include "ngx_http_lua_util.h"
#include "ngx_http_lua_hook.h"

static void init_ngx_lua_registry(lua_State *l);
static void init_ngx_lua_globals(lua_State *l);

lua_State*
ngx_http_lua_newstate()
{
	lua_State *l = luaL_newstate();
	if(l == NULL) {
		return NULL;
	}

	init_ngx_lua_registry(l);
	init_ngx_lua_globals(l);

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

static void
init_ngx_lua_registry(lua_State *l)
{
	// {{{ register table to anchor lua coroutines reliablly: {([int]ref) = [cort]}
	lua_newtable(l);
	lua_setfield(l, LUA_REGISTRYINDEX, NGX_LUA_CORT_REF);
	// }}}
	// {{{ register table to cache user code: {([string]cache_key) = [code closure]}
	lua_newtable(l);
	lua_setfield(l, LUA_REGISTRYINDEX, LUA_CODE_CACHE_KEY);
	// }}}
}

static void
init_ngx_lua_globals(lua_State *l)
{
	// replace main thread's globals with new environment
	lua_newtable(l);

	// XXX: must replace main thread's globals table before opening standard
	// libs, otherwise we'll need to inherit original globals table here.
	/*
	lua_newtable(l);
	lua_pushvalue(l, LUA_GLOBALSINDEX);
	lua_setfield(l, -2, "__index");
	lua_setmetatable(l, -2);
	*/

	lua_newtable(l);	// ngx.*

	// {{{ register nginx hook functions
	/*
	lua_pushcfunction(l, ngx_foo);
	lua_setfield(l, -2, "foo");
	lua_pushcfunction(l, ngx_bar);
	lua_setfield(l, -2, "bar");
	*/
	// }}}

	// {{{ register nginx constants
	lua_newtable(l);	// .status

	lua_pushinteger(l, 200);
	lua_setfield(l, -2, "HTTP_OK");
	lua_pushinteger(l, 302);
	lua_setfield(l, -2, "HTTP_LOCATION");

	lua_setfield(l, -2, "status");
	// }}}

	lua_setfield(l, -2, "ngx");

	lua_replace(l, LUA_GLOBALSINDEX);
}

// vi:ts=4 sw=4 fdm=marker

