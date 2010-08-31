#ifndef NGX_HTTP_LUA_COMMON_H
#define NGX_HTTP_LUA_COMMON_H

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
    lua_State       *lua;
    ngx_str_t        lua_path;
    ngx_str_t        lua_cpath;

} ngx_http_lua_main_conf_t;

typedef struct {
    ngx_str_t        str;
    ngx_uint_t       nargs;
} ngx_http_lua_setby_data_t;

typedef struct {
    ngx_str_t src;    /*  content_by_lua inline script / script file path */
} ngx_http_lua_loc_conf_t;

typedef struct {
    lua_State       *cc;    /*  coroutine to handle request */
    int              cc_ref;        /*  reference to anchor coroutine in lua registry */
    ngx_flag_t       headers_sent:1;    /*  1: response header has been sent; 0: header not sent yet */
    ngx_flag_t       eof:1;        /*  1: last_buf has been sent; 0: last_buf not sent yet */
    ngx_flag_t       waiting:1;    /*  1: subrequest is still running; 0: subrequest is not running */
    ngx_flag_t       done:1;    /*  1: subrequest is just done; 0: subrequest is not done yet or has already done */
    ngx_flag_t       capture:1;    /*  1: body of current request is to be captured; 0: not captured */
    ngx_chain_t     *sr_body;    /*  all captured subrequest bodies */
    ngx_chain_t     *body;    /*  captured current request body */
    ngx_int_t        sr_status;    /*  captured subrequest status */
    ngx_int_t        error_rc;

    ngx_http_cleanup_pt     *cleanup;
} ngx_http_lua_ctx_t;

typedef enum {
    exec,
    location_capture
} ngx_http_lua_io_cmd_t;

extern ngx_module_t ngx_http_lua_module;
extern ngx_http_output_header_filter_pt ngx_http_lua_next_header_filter;
extern ngx_http_output_body_filter_pt ngx_http_lua_next_body_filter;

/*  user code cache table key in Lua vm registry */
#define LUA_CODE_CACHE_KEY "ngx_http_lua_code_cache"
/*  coroutine anchoring table key in Lua vm registry */
#define NGX_LUA_CORT_REF "ngx_lua_cort_ref"

/*  globals symbol to hold NginX request pointer */
#define GLOBALS_SYMBOL_REQUEST    "ngx._req"
/*  globals symbol to hold code chunk handling NginX request */
#define GLOBALS_SYMBOL_RUNCODE    "ngx._code"

#endif /* NGX_HTTP_LUA_COMMON_H */

