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

#include <nginx.h>
#include <ndk.h>

typedef struct {
	lua_State *lua;
} ngx_http_lua_main_conf_t;

typedef struct {
	ngx_str_t src;	// content_by_lua inline script / script file path
} ngx_http_lua_loc_conf_t;

typedef struct {
	lua_State *cc;	// coroutine to handle request
	int cc_ref;		// reference to anchor coroutine in lua registry
	int headers_sent:1;	// 1: response header has been sent; 0: header not sent yet
	int eof:1;		// 1: last_buf has been sent; 0: last_buf not sent yet
} ngx_http_lua_ctx_t;

extern ngx_module_t ngx_http_lua_module;
extern ngx_http_output_header_filter_pt ngx_http_lua_next_header_filter;
extern ngx_http_output_body_filter_pt ngx_http_lua_next_body_filter;

// user code cache table key in Lua vm registry
#define LUA_CODE_CACHE_KEY "ngx_http_lua_code_cache"
// coroutine anchoring table key in Lua vm registry
#define NGX_LUA_CORT_REF "ngx_lua_cort_ref"

// globals symbol to hold NginX request pointer
#define GLOBALS_SYMBOL_REQUEST	"ngx._req"
// globals symbol to hold code chunk handling NginX request
#define GLOBALS_SYMBOL_RUNCODE	"ngx._code"

#endif

// vi:ts=4 sw=4 fdm=marker

