#ifndef NGX_HTTP_LUA_COMMON_H__
#define NGX_HTTP_LUA_COMMON_H__

#ifndef DDEBUG
#define DDEBUG 0
#endif

#include "ddebug.h"

#include <assert.h>
#include <setjmp.h>

#include <lua.h>
#include <lualib.h>
#include <lauxlib.h>

#include <ndk.h>

extern ngx_module_t ngx_http_lua_module;

// user code cache table key in Lua vm registry
#define LUA_CODE_CACHE_KEY "ngx_http_lua_code_cache"
// coroutine anchoring table key in Lua vm registry
#define NGX_LUA_CORT_REF "ngx_lua_cort_ref"

// globals symbol to hold NginX request pointer
#define GLOBALS_SYMBOL_REQUEST "ngx._req"

#endif

// vi:ts=4 sw=4 fdm=marker

