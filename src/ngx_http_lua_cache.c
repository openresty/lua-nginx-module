#define DDEBUG 1
#include "ddebug.h"

#include <ngx_md5.h>
#include "ngx_http_lua_cache.h"
#include "ngx_http_lua_clfactory.h"

#define IL_TAG "nhli_"
#define IL_TAG_LEN (sizeof(IL_TAG) - 1)

static u_char *
ngx_http_lua_digest_hex(u_char *dest, const u_char *buf, int buf_len)
{
	u_char digest[MD5_DIGEST_LENGTH];
	MD5(buf, buf_len, digest);
	return ngx_hex_dump(dest, digest, sizeof(digest));
}


/**
 * Find code chunk associated with the given key in code cache,
 * and push it to the top of Lua stack if found.
 *
 * Stack layout before call:
 *         |     ...    | <- top
 *
 * Stack layout after call:
 *         | code chunk | <- top
 *         |     ...    |
 *
 * */
static ngx_int_t
ngx_http_lua_cache_load_code(lua_State *l, const char *ck)
{
	// get code cache table
	lua_getfield(l, LUA_REGISTRYINDEX, LUA_CODE_CACHE_KEY);	// sp++

	dd("Code cache table to load: %p", lua_topointer(l, -1));

	if(!lua_istable(l, -1)) {
		dd("Error: code cache table to load did not exist!!");
		return NGX_ERROR;
	}

	lua_getfield(l, -1, ck);	// sp++
	if(lua_isfunction(l, -1)) {
		// call closure factory to gen new closure
		int rc = lua_pcall(l, 0, 1, 0);

		if(rc == 0) {
			// remove cache table from stack, leave code chunk at top of stack
			lua_remove(l, -2);                        // sp--
			return NGX_OK;
		}
	}

	dd("Value associated with given key in code cache table is not code chunk: stack top=%d, top value type=%s\n",
			lua_gettop(l), lua_typename(l, -1));

	// remove cache table and value from stack
	lua_pop(l, 2);                                // sp-=2

	return NGX_DECLINED;
}

/**
 * Store the closure factory at the top of Lua stack to code cache, and
 * associate it with the given key. Then generate new closure.
 *
 * Stack layout before call:
 *         | code factory | <- top
 *         |     ...      |
 *
 * Stack layout after call:
 *         | code chunk | <- top
 *         |     ...    |
 *
 * */
static ngx_int_t
ngx_http_lua_cache_store_code(lua_State *l, const char *ck)
{
	int rc;

	// get code cache table
	lua_getfield(l, LUA_REGISTRYINDEX, LUA_CODE_CACHE_KEY);	// sp++

	dd("Code cache table to store: %p", lua_topointer(l, -1));

	if(!lua_istable(l, -1)) {
		dd("Error: code cache table to load did not exist!!");
		return NGX_ERROR;
	}

	lua_pushvalue(l, -2);		// sp++
	lua_setfield(l, -2, ck);	// sp--

	// remove cache table, leave closure factory at top of stack
	lua_pop(l, 1);				// sp--

	// call closure factory to generate new closure
	rc = lua_pcall(l, 0, 1, 0);
	if(rc != 0) {
		dd("Error: failed to call closure factory!!");
		return NGX_ERROR;
	}

	return NGX_OK;
}

ngx_int_t
ngx_http_lua_cache_loadbuffer(
		lua_State *l,
		const u_char *buf,
		int buf_len,
		const char *name
		)
{
	int          rc;
    u_char      *p;
	u_char       cache_key[IL_TAG_LEN + 2*MD5_DIGEST_LENGTH + 1];

    p = ngx_copy(cache_key, IL_TAG, IL_TAG_LEN);

	// calculate digest of inline script
	p = ngx_http_lua_digest_hex(p, buf, buf_len);

    *p = '\0';

    dd("XXX cache key: [%s]", cache_key);

	if (ngx_http_lua_cache_load_code(l, (char *) cache_key) == NGX_OK) {
		// code chunk loaded from cache, sp++
		dd("Code cache hit! cache key='%s', stack top=%d, script='%.*s'", cache_key, lua_gettop(l), buf_len, buf);
		return NGX_OK;
	}

	dd("Code cache missed! cache key='%s', stack top=%d, script='%.*s'", cache_key, lua_gettop(l), buf_len, buf);

	// load closure factory of inline script to the top of lua stack, sp++
	rc = ngx_http_lua_clfactory_loadbuffer(l, (char *) buf, buf_len, name);

	if (rc != 0) {
		dd("Failed to load inline script: script='%.*s'", buf_len, buf);
		return rc;
	}

	// store closure factory and gen new closure at the top of lua stack to code cache
	ngx_http_lua_cache_store_code(l, (char *) cache_key);

	return NGX_OK;
}

ngx_int_t
ngx_http_lua_cache_loadfile(
		lua_State *l,
		const char *script
		)
{
#define FP_TAG "nhlf_"
#define FP_TAG_LEN (sizeof(FP_TAG)-1)
	u_char cache_key[FP_TAG_LEN + 2*MD5_DIGEST_LENGTH + 1] = FP_TAG;
	int rc;

	// calculate digest of script file path
	ngx_http_lua_digest_hex(&cache_key[FP_TAG_LEN], (u_char *) script, ngx_strlen(script));

    dd("XXX cache key for file: [%s]", cache_key);

	if(ngx_http_lua_cache_load_code(l, (char *) cache_key) == NGX_OK) {
		// code chunk loaded from cache, sp++
		dd("Code cache hit! cache key='%s', stack top=%d, file path='%s'", cache_key, lua_gettop(l), script);
		return NGX_OK;
	}

	dd("Code cache missed! cache key='%s', stack top=%d, file path='%s'", cache_key, lua_gettop(l), script);

	// load closure factory of script file to the top of lua stack, sp++
	rc = ngx_http_lua_clfactory_loadfile(l, script);
	if(rc) {
		dd("Failed to load script file: file path='%s'", script);
		return rc;
	}

	// store closure factory and gen new closure at the top of lua stack to code cache
	ngx_http_lua_cache_store_code(l, (char *) cache_key);

	return NGX_OK;
}

// vi:ts=4 sw=4 fdm=marker

