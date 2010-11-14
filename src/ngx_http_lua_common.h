/* vim:set ft=c ts=4 sw=4 et fdm=marker: */
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
#include <ngx_md5.h>


typedef struct {
    lua_State       *lua;
    ngx_str_t        lua_path;
    ngx_str_t        lua_cpath;

} ngx_http_lua_main_conf_t;

typedef struct {
    ngx_flag_t  force_read_body;    /* 1: force request body to be read; 0: don't force reading request body */
    ngx_str_t   src;                /*  content_by_lua inline script / script file path */
} ngx_http_lua_loc_conf_t;

typedef struct {
    lua_State       *cc;                /*  coroutine to handle request */
    int              cc_ref;            /*  reference to anchor coroutine in lua registry */

    ngx_http_headers_out_t   *sr_headers;

    ngx_chain_t     *sr_body;           /*  all captured subrequest bodies */
    ngx_chain_t     *body;              /*  captured current request body */
    ngx_int_t        sr_status;         /*  captured subrequest status */

    ngx_str_t        exec_uri;
    ngx_str_t        exec_args;

    ngx_int_t        exit_code;
    ngx_flag_t       exited:1;

    ngx_flag_t       headers_sent:1;    /*  1: response header has been sent; 0: header not sent yet */
    ngx_flag_t       eof:1;             /*  1: last_buf has been sent; 0: last_buf not sent yet */
    ngx_flag_t       waiting:1;         /*  1: subrequest is still running; 0: subrequest is not running */
    ngx_flag_t       done:1;            /*  1: subrequest is just done; 0: subrequest is not done yet or has already done */
    ngx_flag_t       capture:1;         /*  1: body of current request is to be captured; 0: not captured */

    ngx_flag_t       read_body_done:1;      /* 1: request body has been all read; 0: body has not been all read */
    ngx_flag_t       waiting_more_body:1;   /* 1: waiting for more data; 0: no need to wait */
    ngx_flag_t       headers_set:1;

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

