/* vim:set ft=c ts=4 sw=4 et fdm=marker: */

#define DDEBUG 0

#include "ngx_http_lua_directive.h"
#include "ngx_http_lua_util.h"
#include "ngx_http_lua_cache.h"
#include "ngx_http_lua_conf.h"
#include "ngx_http_lua_setby.h"
#include "ngx_http_lua_contentby.h"
#include "ngx_http_lua_accessby.h"
#include "ngx_http_lua_rewriteby.h"


unsigned  ngx_http_lua_requires_rewrite = 0;
unsigned  ngx_http_lua_requires_access  = 0;


char *
ngx_http_lua_code_cache(ngx_conf_t *cf, ngx_command_t *cmd, void *conf)
{
    ngx_conf_log_error(NGX_LOG_WARN, cf, 0,
            "lua_code_cache is off, this will hurt performance");

    return ngx_conf_set_flag_slot(cf, cmd, conf);
}


char *
ngx_http_lua_package_cpath(ngx_conf_t *cf, ngx_command_t *cmd, void *conf)
{
    ngx_http_lua_main_conf_t *lmcf = conf;
    ngx_str_t                *value;

    if (lmcf->lua_cpath.len != 0) {
        return "is duplicate";
    }

    dd("enter");

    value = cf->args->elts;

    lmcf->lua_cpath.len = value[1].len;
    lmcf->lua_cpath.data = value[1].data;

    return NGX_CONF_OK;
}


char *
ngx_http_lua_package_path(ngx_conf_t *cf, ngx_command_t *cmd, void *conf)
{
    ngx_http_lua_main_conf_t *lmcf = conf;
    ngx_str_t                *value;

    if (lmcf->lua_path.len != 0) {
        return "is duplicate";
    }

    dd("enter");

    value = cf->args->elts;

    lmcf->lua_path.len = value[1].len;
    lmcf->lua_path.data = value[1].data;

    return NGX_CONF_OK;
}


char *
ngx_http_lua_set_by_lua(ngx_conf_t *cf, ngx_command_t *cmd, void *conf)
{
    ngx_str_t           *args;
    ngx_str_t            target;
    ndk_set_var_t        filter;

    /*
     * args[0] = "set_by_lua"
     * args[1] = target variable name
     * args[2] = lua script to be executed
     * args[3..] = real params
     * */
    args = cf->args->elts;
    target = args[1];

    /*  prevent variable appearing in Lua inline script/file path */

#if 0
    if (ngx_http_lua_has_inline_var(&args[2])) {
        ngx_conf_log_error(NGX_LOG_ERR, cf, 0,
                "Lua inline script or file path should not has inline variable: %V",
                &args[2]);
        return NGX_CONF_ERROR;
    }
#endif

    filter.type = NDK_SET_VAR_MULTI_VALUE_DATA;
    filter.func = cmd->post;
    filter.size = cf->args->nelts - 2;    /*  get number of real params + 1 (lua script) */
    filter.data = (void*)filter.size;

    return ndk_set_var_multi_value_core(cf, &target, &args[2], &filter);
}


ngx_int_t
ngx_http_lua_filter_set_by_lua_inline(ngx_http_request_t *r, ngx_str_t *val,
        ngx_http_variable_value_t *v, void *data)
{
    lua_State                   *L;
    ngx_int_t                    rc;
    ngx_http_lua_main_conf_t    *lmcf;
    ngx_http_lua_loc_conf_t     *llcf;
    char                        *err = NULL;

    lmcf = ngx_http_get_module_main_conf(r, ngx_http_lua_module);

    L = lmcf->lua;

    llcf = ngx_http_get_module_loc_conf(r, ngx_http_lua_module);

    /*  load Lua inline script (w/ cache)        sp = 1 */
    rc = ngx_http_lua_cache_loadbuffer(L, v[0].data, v[0].len,
            "set_by_lua_inline", &err, llcf->enable_code_cache);

    if (rc != NGX_OK) {
        if (err == NULL) {
            err = "unknown error";
        }

        ngx_log_error(NGX_LOG_ERR, r->connection->log, 0,
                "Failed to load Lua inlined code: %s", err);

        return NGX_ERROR;
    }

    rc = ngx_http_lua_set_by_chunk(L, r, val, v, (size_t) data);
    if (rc != NGX_OK) {
        return NGX_ERROR;
    }

    return NGX_OK;
}


ngx_int_t
ngx_http_lua_filter_set_by_lua_file(ngx_http_request_t *r, ngx_str_t *val,
        ngx_http_variable_value_t *v, void *data)
{
    lua_State                   *L;
    ngx_int_t                    rc;
    u_char                      *script_path;
    ngx_http_lua_main_conf_t    *lmcf;
    ngx_http_lua_loc_conf_t     *llcf;
    char                        *err;

    script_path = ngx_http_lua_rebase_path(r->pool, v[0].data, v[0].len);

    if (script_path == NULL) {
        ngx_log_error(NGX_LOG_ERR, r->connection->log, 0,
                "Failed to allocate memory to store absolute path: raw path='%v'",
                &v[0]);

        return NGX_ERROR;
    }

    lmcf = ngx_http_get_module_main_conf(r, ngx_http_lua_module);

    L = lmcf->lua;

    llcf = ngx_http_get_module_loc_conf(r, ngx_http_lua_module);

    /*  load Lua script file (w/ cache)        sp = 1 */
    rc = ngx_http_lua_cache_loadfile(L, (char *)script_path, &err,
            llcf->enable_code_cache);

    if (rc != NGX_OK) {
        if (err == NULL) {
            err = "unknown error";
        }

        ngx_log_error(NGX_LOG_ERR, r->connection->log, 0,
                "Failed to load Lua file: %s", err);

        return NGX_ERROR;
    }

    rc = ngx_http_lua_set_by_chunk(L, r, val, v, (size_t) data);
    if (rc != NGX_OK) {
        return NGX_ERROR;
    }

    return NGX_OK;
}


char *
ngx_http_lua_rewrite_by_lua(ngx_conf_t *cf, ngx_command_t *cmd, void *conf)
{
    ngx_str_t                   *args;
    ngx_http_lua_loc_conf_t     *llcf = conf;

    dd("enter");

    /*  must specifiy a content handler */
    if (cmd->post == NULL) {
        return NGX_CONF_ERROR;
    }

    if (llcf->rewrite_handler) {
        return "is duplicate";
    }

    /*  update lua script data */
    /*
     * args[0] = "content_by_lua"
     * args[1] = lua script to be executed
     * */
    args = cf->args->elts;

    /*  prevent variable appearing in Lua inline script/file path */

#if 0
    if (ngx_http_lua_has_inline_var(&args[1])) {
        ngx_conf_log_error(NGX_LOG_ERR, cf, 0,
                "Lua inline script or file path should not has inline "
                "variable: %V",
                &args[1]);

        return NGX_CONF_ERROR;
    }
#endif

    if (args[1].len == 0) {
        /*  Oops...Invalid location conf */
        ngx_conf_log_error(NGX_LOG_ERR, cf, 0,
                "Invalid location config: no runnable Lua code");
        return NGX_CONF_ERROR;
    }

    if(cmd->post == ngx_http_lua_rewrite_handler_inline) {
        /* Don't eval NginX variables for inline lua code */
        llcf->rewrite_src.raw_value = args[1];
        llcf->rewrite_src.lengths = NULL;
        llcf->rewrite_src.values = NULL;
    } else {
        if(ngx_http_lua_arg_compile(cf, &llcf->rewrite_src, &args[1]) != NGX_CONF_OK) {
            ngx_conf_log_error(NGX_LOG_ERR, cf, 0,
                    "Failed to compile rewrite_by_lua code path: %V", &args[1]);

            return NGX_CONF_ERROR;
        }
    }
    llcf->rewrite_handler = cmd->post;

    if (! ngx_http_lua_requires_rewrite) {
        ngx_http_lua_requires_rewrite = 1;
    }

    return NGX_CONF_OK;
}


char *
ngx_http_lua_access_by_lua(ngx_conf_t *cf, ngx_command_t *cmd, void *conf)
{
    ngx_str_t                   *args;
    ngx_http_lua_loc_conf_t     *llcf = conf;

    dd("enter");

    /*  must specifiy a content handler */
    if (cmd->post == NULL) {
        return NGX_CONF_ERROR;
    }

    if (llcf->access_handler) {
        return "is duplicate";
    }

    /*  update lua script data */
    /*
     * args[0] = "content_by_lua"
     * args[1] = lua script to be executed
     * */
    args = cf->args->elts;

    /*  prevent variable appearing in Lua inline script/file path */

#if 0
    if (ngx_http_lua_has_inline_var(&args[1])) {
        ngx_conf_log_error(NGX_LOG_ERR, cf, 0,
                "Lua inline script or file path should not has inline "
                "variable: %V",
                &args[1]);

        return NGX_CONF_ERROR;
    }
#endif

    if (args[1].len == 0) {
        /*  Oops...Invalid location conf */
        ngx_conf_log_error(NGX_LOG_ERR, cf, 0,
                "Invalid location config: no runnable Lua code");

        return NGX_CONF_ERROR;
    }

    if(cmd->post == ngx_http_lua_access_handler_inline) {
        /* Don't eval NginX variables for inline lua code */
        llcf->access_src.raw_value = args[1];
        llcf->access_src.lengths = NULL;
        llcf->access_src.values = NULL;
    } else {
        if(ngx_http_lua_arg_compile(cf, &llcf->access_src, &args[1]) != NGX_CONF_OK) {
            ngx_conf_log_error(NGX_LOG_ERR, cf, 0,
                    "Failed to compile access_by_lua code path: %V", &args[1]);

            return NGX_CONF_ERROR;
        }
    }
    llcf->access_handler = cmd->post;

    if (! ngx_http_lua_requires_access) {
        ngx_http_lua_requires_access = 1;
    }

    return NGX_CONF_OK;
}


char *
ngx_http_lua_content_by_lua(ngx_conf_t *cf, ngx_command_t *cmd, void *conf)
{
    ngx_str_t                   *args;
    ngx_http_core_loc_conf_t    *clcf;
    ngx_http_lua_loc_conf_t     *llcf = conf;

    dd("enter");

    /*  must specifiy a content handler */
    if (cmd->post == NULL) {
        return NGX_CONF_ERROR;
    }

    if (llcf->content_handler) {
        return "is duplicate";
    }

    /*  update lua script data */
    /*
     * args[0] = "content_by_lua"
     * args[1] = lua script to be executed
     * */
    args = cf->args->elts;

    /*  prevent variable appearing in Lua inline script/file path */

#if 0
    if (ngx_http_lua_has_inline_var(&args[1])) {
        ngx_conf_log_error(NGX_LOG_ERR, cf, 0,
                "Lua inline script or file path should not has inline "
                "variable: %V",
                &args[1]);

        return NGX_CONF_ERROR;
    }
#endif

    if (args[1].len == 0) {
        /*  Oops...Invalid location conf */
        ngx_conf_log_error(NGX_LOG_ERR, cf, 0,
                "Invalid location config: no runnable Lua code");
        return NGX_CONF_ERROR;
    }

    if(cmd->post == ngx_http_lua_content_handler_inline) {
        /* Don't eval NginX variables for inline lua code */
        llcf->content_src.raw_value = args[1];
        llcf->content_src.lengths = NULL;
        llcf->content_src.values = NULL;

    } else {
        if(ngx_http_lua_arg_compile(cf, &llcf->content_src, &args[1]) != NGX_CONF_OK) {
            ngx_conf_log_error(NGX_LOG_ERR, cf, 0,
                    "Failed to compile content_by_lua code path: %V", &args[1]);

            return NGX_CONF_ERROR;
        }
    }
    llcf->content_handler = cmd->post;

    /*  register location content handler */
    clcf = ngx_http_conf_get_module_loc_conf(cf, ngx_http_core_module);
    if (clcf == NULL) {
        return NGX_CONF_ERROR;
    }

    clcf->handler = ngx_http_lua_content_handler;

    return NGX_CONF_OK;
}

