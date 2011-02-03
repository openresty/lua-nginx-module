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


/* Nginx HTTP Lua Inline tag prefix */

#define NGX_HTTP_LUA_INLINE_TAG "nhli_"

#define NGX_HTTP_LUA_INLINE_TAG_LEN \
    (sizeof(NGX_HTTP_LUA_INLINE_TAG) - 1)

#define NGX_HTTP_LUA_INLINE_KEY_LEN \
    (NGX_HTTP_LUA_INLINE_TAG_LEN + 2 * MD5_DIGEST_LENGTH)

/* Nginx HTTP Lua File tag prefix */

#define NGX_HTTP_LUA_FILE_TAG "nhlf_"

#define NGX_HTTP_LUA_FILE_TAG_LEN \
    (sizeof(NGX_HTTP_LUA_FILE_TAG) - 1)

#define NGX_HTTP_LUA_FILE_KEY_LEN \
    (NGX_HTTP_LUA_FILE_TAG_LEN + 2 * MD5_DIGEST_LENGTH)


typedef struct {
    size_t       size;
    u_char      *key;
} ngx_http_lua_set_var_data_t;

typedef struct {
    lua_State       *lua;
    ngx_str_t        lua_path;
    ngx_str_t        lua_cpath;

    unsigned    postponed_to_rewrite_phase_end:1;
    unsigned    postponed_to_access_phase_end:1;

} ngx_http_lua_main_conf_t;


typedef struct {
    ngx_flag_t              force_read_body; /* whether force request body to
                                                be read */

    ngx_flag_t              enable_code_cache; /* whether to enable
                                                  code cache */

    ngx_http_handler_pt     rewrite_handler;
    ngx_http_handler_pt     access_handler;
    ngx_http_handler_pt     content_handler;

    ngx_http_complex_value_t rewrite_src;    /*  rewrite_by_lua
                                                inline script/script
                                                file path */

    u_char                 *rewrite_src_key; /* cached key for rewrite_src */

    ngx_http_complex_value_t access_src;     /*  access_by_lua
                                                inline script/script
                                                file path */

    u_char                  *access_src_key; /* cached key for access_src */

    ngx_http_complex_value_t content_src;    /*  content_by_lua
                                                inline script/script
                                                file path */

    u_char                 *content_src_key; /* cached key for content_src */

} ngx_http_lua_loc_conf_t;


typedef struct {
    lua_State       *cc;                /*  coroutine to handle request */
    int              cc_ref;            /*  reference to anchor coroutine
                                            in lua registry */

    ngx_http_cleanup_pt     *cleanup;

    ngx_chain_t     *body;              /*  captured current request body */

#if 0
    ngx_chain_t     *sr_body;           /*  all captured subrequest bodies */
    ngx_int_t        sr_status;         /*  captured subrequest status */
#endif

    ngx_uint_t       nsubreqs;    /* number of subrequests of the
                                     current request */

    ngx_http_headers_out_t  **sr_headers;

    unsigned        *waitings;    /* all subrequests waiting flags */
    ngx_chain_t    **sr_bodies;   /* all captured subrquest bodies */
    ngx_int_t       *sr_statuses; /* all capture subrequest statuses */
    ngx_uint_t       index; /* index of the current subrequest in its
                               parent request */

    ngx_str_t        exec_uri;
    ngx_str_t        exec_args;

    ngx_int_t        exit_code;
    ngx_flag_t       exited:1;

    unsigned       headers_sent:1;    /*  1: response header has been sent;
                                            0: header not sent yet */

    unsigned       eof:1;             /*  1: last_buf has been sent;
                                            0: last_buf not sent yet */

    unsigned       waiting:1;         /*  1: subrequest is still running;
                                            0: subrequest is not running */

    unsigned       done:1;            /*  1: subrequest is just done;
                                            0: subrequest is not done
                                            yet or has already done */

    unsigned       capture:1;         /*  1: body of current request is
                                            to be captured;
                                            0: not captured */

    unsigned       read_body_done:1;      /* 1: request body has been all
                                               read; 0: body has not been
                                               all read */

    unsigned         waiting_more_body:1;   /* 1: waiting for more data;
                                               0: no need to wait */

    unsigned         headers_set:1;
    unsigned         entered_rewrite_phase:1;
    unsigned         entered_access_phase:1;
    unsigned         entered_content_phase:1;

    /* whether it has run post_subrequest */
    unsigned         run_post_subrequest:1;

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

