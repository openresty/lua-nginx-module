/* vim:set ft=c ts=4 sw=4 et fdm=marker: */

#include <nginx.h>
#include "ngx_http_lua_directive.h"
#include "ngx_http_lua_conf.h"
#include "ngx_http_lua_capturefilter.h"
#include "ngx_http_lua_contentby.h"
#include "ngx_http_lua_rewriteby.h"
#include "ngx_http_lua_accessby.h"
#include "ngx_http_lua_headerfilterby.h"


#if !defined(nginx_version) || nginx_version < 8054
#error "at least nginx 0.8.54 is required"
#endif


static ngx_int_t ngx_http_lua_init(ngx_conf_t *cf);
static ngx_int_t ngx_http_lua_pre_config(ngx_conf_t *cf);


static ngx_command_t ngx_http_lua_cmds[] = {

    {
        ngx_string("lua_regex_cache_max_entries"),
        NGX_HTTP_MAIN_CONF | NGX_CONF_TAKE1,
        ngx_conf_set_num_slot,
        NGX_HTTP_MAIN_CONF_OFFSET,
        offsetof(ngx_http_lua_main_conf_t, regex_cache_max_entries),
        NULL
    },

    {
        ngx_string("lua_package_cpath"),
        NGX_HTTP_MAIN_CONF | NGX_CONF_TAKE1,
        ngx_http_lua_package_cpath,
        NGX_HTTP_MAIN_CONF_OFFSET,
        0,
        NULL
    },

    {
        ngx_string("lua_package_path"),
        NGX_HTTP_MAIN_CONF | NGX_CONF_TAKE1,
        ngx_http_lua_package_path,
        NGX_HTTP_MAIN_CONF_OFFSET,
        0,
        NULL
    },

    {
        ngx_string("lua_code_cache"),
        NGX_HTTP_MAIN_CONF | NGX_HTTP_SRV_CONF | NGX_HTTP_LOC_CONF |
            NGX_HTTP_LIF_CONF | NGX_CONF_FLAG,
        ngx_http_lua_code_cache,
        NGX_HTTP_LOC_CONF_OFFSET,
        offsetof(ngx_http_lua_loc_conf_t, enable_code_cache),
        NULL
    },

    {
        ngx_string("lua_need_request_body"),
        NGX_HTTP_MAIN_CONF | NGX_HTTP_SRV_CONF | NGX_HTTP_LOC_CONF |
            NGX_HTTP_LIF_CONF | NGX_CONF_FLAG,
        ngx_conf_set_flag_slot,
        NGX_HTTP_LOC_CONF_OFFSET,
        offsetof(ngx_http_lua_loc_conf_t, force_read_body),
        NULL
    },

#if defined(NDK) && NDK
    /* set_by_lua $res <inline script> [$arg1 [$arg2 [...]]] */
    {
        ngx_string("set_by_lua"),
        NGX_HTTP_MAIN_CONF | NGX_HTTP_SRV_CONF | NGX_HTTP_SIF_CONF |
            NGX_HTTP_LOC_CONF | NGX_HTTP_LIF_CONF | NGX_CONF_2MORE,
        ngx_http_lua_set_by_lua,
        NGX_HTTP_LOC_CONF_OFFSET,
        0,
        ngx_http_lua_filter_set_by_lua_inline
    },

    /* set_by_lua_file $res rel/or/abs/path/to/script [$arg1 [$arg2 [..]]] */
    {
        ngx_string("set_by_lua_file"),
        NGX_HTTP_MAIN_CONF | NGX_HTTP_SRV_CONF | NGX_HTTP_SIF_CONF |
            NGX_HTTP_LOC_CONF | NGX_HTTP_LIF_CONF | NGX_CONF_2MORE,
        ngx_http_lua_set_by_lua,
        NGX_HTTP_LOC_CONF_OFFSET,
        0,
        ngx_http_lua_filter_set_by_lua_file
    },
#endif

    /* rewrite_by_lua <inline script> */
    {
        ngx_string("rewrite_by_lua"),
        NGX_HTTP_MAIN_CONF | NGX_HTTP_SRV_CONF | NGX_HTTP_LOC_CONF |
            NGX_HTTP_LIF_CONF | NGX_CONF_TAKE1,
        ngx_http_lua_rewrite_by_lua,
        NGX_HTTP_LOC_CONF_OFFSET,
        0,
        ngx_http_lua_rewrite_handler_inline
    },

    /* access_by_lua <inline script> */
    {
        ngx_string("access_by_lua"),
        NGX_HTTP_MAIN_CONF | NGX_HTTP_SRV_CONF | NGX_HTTP_LOC_CONF |
            NGX_HTTP_LIF_CONF | NGX_CONF_TAKE1,
        ngx_http_lua_access_by_lua,
        NGX_HTTP_LOC_CONF_OFFSET,
        0,
        ngx_http_lua_access_handler_inline
    },

    /* content_by_lua <inline script> */
    {
        ngx_string("content_by_lua"),
        NGX_HTTP_LOC_CONF | NGX_HTTP_LIF_CONF | NGX_CONF_TAKE1,
        ngx_http_lua_content_by_lua,
        NGX_HTTP_LOC_CONF_OFFSET,
        0,
        ngx_http_lua_content_handler_inline
    },

    /* header_filter_by_lua <inline script> */
    {
        ngx_string("header_filter_by_lua"),
        NGX_HTTP_MAIN_CONF | NGX_HTTP_SRV_CONF | NGX_HTTP_LOC_CONF |
            NGX_HTTP_LIF_CONF | NGX_CONF_TAKE1,
        ngx_http_lua_header_filter_by_lua,
        NGX_HTTP_LOC_CONF_OFFSET,
        0,
        ngx_http_lua_header_filter_inline
    },

    {
        ngx_string("rewrite_by_lua_file"),
        NGX_HTTP_MAIN_CONF | NGX_HTTP_SRV_CONF | NGX_HTTP_LOC_CONF |
            NGX_HTTP_LIF_CONF | NGX_CONF_TAKE1,
        ngx_http_lua_rewrite_by_lua,
        NGX_HTTP_LOC_CONF_OFFSET,
        0,
        ngx_http_lua_rewrite_handler_file
    },

    {
        ngx_string("access_by_lua_file"),
        NGX_HTTP_MAIN_CONF | NGX_HTTP_SRV_CONF | NGX_HTTP_LOC_CONF |
            NGX_HTTP_LIF_CONF | NGX_CONF_TAKE1,
        ngx_http_lua_access_by_lua,
        NGX_HTTP_LOC_CONF_OFFSET,
        0,
        ngx_http_lua_access_handler_file
    },

    /* content_by_lua_file rel/or/abs/path/to/script */
    {
        ngx_string("content_by_lua_file"),
        NGX_HTTP_LOC_CONF | NGX_HTTP_LIF_CONF | NGX_CONF_TAKE1,
        ngx_http_lua_content_by_lua,
        NGX_HTTP_LOC_CONF_OFFSET,
        0,
        ngx_http_lua_content_handler_file
    },

    {
        ngx_string("header_filter_by_lua_file"),
        NGX_HTTP_MAIN_CONF | NGX_HTTP_SRV_CONF | NGX_HTTP_LOC_CONF |
            NGX_HTTP_LIF_CONF | NGX_CONF_TAKE1,
        ngx_http_lua_header_filter_by_lua,
        NGX_HTTP_LOC_CONF_OFFSET,
        0,
        ngx_http_lua_header_filter_file
    },

    ngx_null_command
};

ngx_http_module_t ngx_http_lua_module_ctx = {
    ngx_http_lua_pre_config,          /*  preconfiguration */
    ngx_http_lua_init,                /*  postconfiguration */

    ngx_http_lua_create_main_conf,    /*  create main configuration */
    ngx_http_lua_init_main_conf,      /*  init main configuration */

    NULL,                             /*  create server configuration */
    NULL,                             /*  merge server configuration */

    ngx_http_lua_create_loc_conf,     /*  create location configuration */
    ngx_http_lua_merge_loc_conf       /*  merge location configuration */
};


ngx_module_t ngx_http_lua_module = {
    NGX_MODULE_V1,
    &ngx_http_lua_module_ctx,   /*  module context */
    ngx_http_lua_cmds,          /*  module directives */
    NGX_HTTP_MODULE,            /*  module type */
    NULL,                       /*  init master */
    NULL,                       /*  init module */
    NULL,                       /*  init process */
    NULL,                       /*  init thread */
    NULL,                       /*  exit thread */
    NULL,                       /*  exit process */
    NULL,                       /*  exit master */
    NGX_MODULE_V1_PADDING
};


static ngx_int_t
ngx_http_lua_init(ngx_conf_t *cf)
{
    ngx_int_t                   rc;
    ngx_http_handler_pt        *h;
    ngx_http_core_main_conf_t  *cmcf;

    rc = ngx_http_lua_capture_filter_init(cf);
    if (rc != NGX_OK) {
        return rc;
    }

    cmcf = ngx_http_conf_get_module_main_conf(cf, ngx_http_core_module);

    if (ngx_http_lua_requires_rewrite) {
        h = ngx_array_push(&cmcf->phases[NGX_HTTP_REWRITE_PHASE].handlers);
        if (h == NULL) {
            return NGX_ERROR;
        }

        *h = ngx_http_lua_rewrite_handler;
    }

    if (ngx_http_lua_requires_access) {
        h = ngx_array_push(&cmcf->phases[NGX_HTTP_ACCESS_PHASE].handlers);
        if (h == NULL) {
            return NGX_ERROR;
        }

        *h = ngx_http_lua_access_handler;
    }

    if (ngx_http_lua_requires_header_filter) {
        rc = ngx_http_lua_header_filter_init(cf);
        if (rc != NGX_OK) {
            return rc;
        }
    }

    return NGX_OK;
}


static ngx_int_t
ngx_http_lua_pre_config(ngx_conf_t *cf)
{
    ngx_http_lua_requires_rewrite = 0;
    ngx_http_lua_requires_access = 0;
    ngx_http_lua_requires_header_filter = 0;
    ngx_http_lua_requires_capture_filter = 0;

    return NGX_OK;
}

