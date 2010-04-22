#include "ngx_md5.h"
#include "ngx_http_lua_cache.h"

static const char*
ngx_http_lua_digest_hex(char *dest, const char *buf, int buf_len)
{
	char temp[MD5_DIGEST_LENGTH];
	MD5((const u_char*)buf, buf_len, (u_char*)temp);
	return (const char*)ngx_hex_dump((u_char*)dest, (u_char*)temp, sizeof(temp));
}

#define LUA_CODE_CACHE_KEY "ngx_http_lua_code_cache"

/**
 * Find code chunk associated with the given key in code cache,
 * and push it to the top of Lua stack if found.
 *
 * Stack layout before call:
 * 		|     ...    | <- top
 *
 * Stack layout after call:
 * 		| code chunk | <- top
 * 		|     ...    |
 *
 * */
static ngx_int_t
ngx_http_lua_cache_load_code(lua_State *l, const char *ck)
{
	// get code cache table
	lua_pushstring(l, LUA_CODE_CACHE_KEY);		// sp++
	lua_gettable(l, LUA_REGISTRYINDEX);			// sp=sp

	dd("Code cache table to load: %p", lua_topointer(l, -1));

	if(!lua_istable(l, -1)) {
		dd("Code cache table to load not exists, create one!");
		lua_pop(l, 1);	// remove unused value	// sp--

		lua_pushstring(l, LUA_CODE_CACHE_KEY);	// sp++
		lua_newtable(l);						// sp++
		lua_settable(l, LUA_REGISTRYINDEX);		// sp-=2

		// get new cache table
		lua_pushstring(l, LUA_CODE_CACHE_KEY);	// sp++
		lua_gettable(l, LUA_REGISTRYINDEX);		// sp=sp
		dd("New code cache table to load: %p", lua_topointer(l, -1));
	}

	lua_pushstring(l, ck);						// sp++
	lua_gettable(l, -2);						// sp=sp
	if(lua_isfunction(l, -1) || lua_iscfunction(l, -1)) {
		// remove cache table from stack, leave code chunk at top of stack
		lua_remove(l, -2);						// sp--
		return NGX_OK;
	}

	dd("Value associated with given key in code cache table is not code chunk: stack top=%d, top value type=%s\n",
			lua_gettop(l), lua_typename(l, -1));

	// remove cache table and value from stack
	lua_pop(l, 2);								// sp-=2

	return NGX_DECLINED;
}

/**
 * Store the code chunk at the top of Lua stack to code cache,
 * and associate it with the given key.
 *
 * Stack layout before call:
 * 		| code chunk | <- top
 * 		|     ...    |
 *
 * Stack layout after call:
 * 		| code chunk | <- top
 * 		|     ...    |
 *
 * */
static ngx_int_t
ngx_http_lua_cache_store_code(lua_State *l, const char *ck)
{
	// initial sp > 0
	// get code cache table
	lua_pushstring(l, LUA_CODE_CACHE_KEY);			// sp++
	lua_gettable(l, LUA_REGISTRYINDEX);				// sp=sp

	dd("Code cache table to store: %p", lua_topointer(l, -1));

	if(!lua_istable(l, -1)) {
		dd("Code cache table to store not exists, create one!");
		lua_pop(l, 1);	// remove unused value			sp--

		lua_pushstring(l, LUA_CODE_CACHE_KEY);		// sp++
		lua_newtable(l);							// sp++
		lua_settable(l, LUA_REGISTRYINDEX);			// sp-=2

		// get new cache table
		lua_pushstring(l, LUA_CODE_CACHE_KEY);		// sp++
		lua_gettable(l, LUA_REGISTRYINDEX);			// sp=sp
		dd("New code cache table to store: %p", lua_topointer(l, -1));
	}

	lua_pushstring(l, ck);							// sp++

	/**
	 * now the stack layout is:
	 * 		| cache key  | <- top
	 * 		|   table    |
	 * 		| code chunk |
	 * */

	lua_pushvalue(l, -3);							// sp++

	/**
	 * now the stack layout is:
	 * 		| code chunk | <- top
	 * 		| cache key  |
	 * 		|   table    |
	 * 		| code chunk |
	 * */

	lua_settable(l, -3);							// sp-=2

	// remove cache table, leave code chunk at top of stack
	lua_pop(l, 1);									// sp--

	return NGX_OK;
}

ngx_int_t
ngx_http_lua_cache_loadbuffer(
		lua_State *l,
		const char *buf,
		int buf_len,
		const char *name
		)
{
#define IL_TAG "ngx_http_lua_il_"
#define IL_TAG_LEN (sizeof(IL_TAG)-1)
	char cache_key[IL_TAG_LEN + 2*MD5_DIGEST_LENGTH + 1] = IL_TAG;
	int rc;

	// calculate digest of inline script
	ngx_http_lua_digest_hex(&cache_key[IL_TAG_LEN], buf, buf_len);

	if(ngx_http_lua_cache_load_code(l, cache_key) == NGX_OK) {
		// code chunk loaded from cache, sp++
		dd("Code cache hit! cache key='%s', stack top=%d, script='%.*s'", cache_key, lua_gettop(l), buf_len, buf);
		return NGX_OK;
	}

	dd("Code cache missed! cache key='%s', stack top=%d, script='%.*s'", cache_key, lua_gettop(l), buf_len, buf);

	// load inline script to the top of lua stack, sp++
	rc = luaL_loadbuffer(l, buf, buf_len, name);
	if(rc) {
		dd("Failed to load inline script: script='%.*s'", buf_len, buf);
		return rc;
	}

	// store function at the top of lua stack to code cache
	ngx_http_lua_cache_store_code(l, cache_key);

	return NGX_OK;
}

ngx_int_t
ngx_http_lua_cache_loadfile(
		lua_State *l,
		const char *script
		)
{
#define FP_TAG "ngx_http_lua_fp_"
#define FP_TAG_LEN (sizeof(FP_TAG)-1)
	char cache_key[FP_TAG_LEN + 2*MD5_DIGEST_LENGTH + 1] = FP_TAG;
	int rc;

	// calculate digest of script file path
	ngx_http_lua_digest_hex(&cache_key[FP_TAG_LEN], script, ngx_strlen(script));

	if(ngx_http_lua_cache_load_code(l, cache_key) == NGX_OK) {
		// code chunk loaded from cache, sp++
		dd("Code cache hit! cache key='%s', stack top=%d, file path='%s'", cache_key, lua_gettop(l), script);
		return NGX_OK;
	}

	dd("Code cache missed! cache key='%s', stack top=%d, file path='%s'", cache_key, lua_gettop(l), script);

	// load script file to the top of lua stack, sp++
	rc = luaL_loadfile(l, script);
	if(rc) {
		dd("Failed to load script file: file path='%s'", script);
		return rc;
	}

	// store function at the top of lua stack to code cache
	ngx_http_lua_cache_store_code(l, cache_key);

	return NGX_OK;
}

