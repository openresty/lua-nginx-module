
/*
 * Copyright (C) Yichun Zhang (agentzh)
 *
 * Author: Thibault Charbonnier (thibaultcha)
 * I hereby assign copyright in this code to the lua-nginx-module project,
 * to be licensed under the same terms as the rest of the code.
 */


#ifndef DDEBUG
#define DDEBUG 0
#endif


#include "ddebug.h"
#include "ngx_http_lua_configureby.h"
#include "ngx_http_lua_directive.h"
#include "ngx_http_lua_util.h"
#include "ngx_http_lua_shdict.h"
#include "ngx_http_lua_api.h"


static ngx_conf_t *cfp;


char *
ngx_http_lua_configure_by_lua_block(ngx_conf_t *cf, ngx_command_t *cmd,
    void *conf)
{
    char        *rv;
    ngx_conf_t   save;

    save = *cf;
    cf->handler = ngx_http_lua_configure_by_lua;
    cf->handler_conf = conf;

    rv = ngx_http_lua_conf_lua_block_parse(cf, cmd);

    *cf = save;

    return rv;
}


char *
ngx_http_lua_configure_by_lua(ngx_conf_t *cf, ngx_command_t *cmd,
    void *conf)
{
    u_char                      *name;
    ngx_str_t                   *value;
    ngx_http_lua_main_conf_t    *lmcf = conf;

    if (cmd->post == NULL) {
        return NGX_CONF_ERROR;
    }

    if (lmcf->configure_handler) {
        return "is duplicate";
    }

    value = cf->args->elts;

    if (value[1].len == 0) {
        ngx_conf_log_error(NGX_LOG_ERR, cf, 0,
                           "invalid location config: no runnable Lua code");
        return NGX_CONF_ERROR;
    }

    lmcf->configure_handler = (ngx_http_lua_configure_handler_pt) cmd->post;

    if (cmd->post == ngx_http_lua_configure_handler_file) {
        name = ngx_http_lua_rebase_path(cf->pool, value[1].data,
                                        value[1].len);
        if (name == NULL) {
            return NGX_CONF_ERROR;
        }

        lmcf->configure_src.data = name;
        lmcf->configure_src.len = ngx_strlen(name);

    } else {
        lmcf->configure_src = value[1];
    }

    return NGX_CONF_OK;
}


ngx_int_t
ngx_http_lua_configure_handler_inline(ngx_conf_t *cf,
    ngx_http_lua_main_conf_t *lmcf)
{
    int             status;
    lua_State      *L = lmcf->lua;

    cfp = cf;

    status = luaL_loadbuffer(L, (char *) lmcf->configure_src.data,
                             lmcf->configure_src.len, "=configure_by_lua")
             || ngx_http_lua_do_call(cf->log, L);

    cfp = NULL;

    return ngx_http_lua_report(cf->log, L, status, "configure_by_lua");
}


ngx_int_t
ngx_http_lua_configure_handler_file(ngx_conf_t *cf,
    ngx_http_lua_main_conf_t *lmcf)
{
    int             status;
    lua_State      *L = lmcf->lua;

    cfp = cf;

    status = luaL_loadfile(L, (char *) lmcf->configure_src.data)
             || ngx_http_lua_do_call(cf->log, L);

    cfp = NULL;

    return ngx_http_lua_report(cf->log, L, status, "configure_by_lua_file");
}


ngx_uint_t
ngx_http_lua_is_configure_phase()
{
    return cfp != NULL;
}


#ifndef NGX_LUA_NO_FFI_API
unsigned int
ngx_http_lua_ffi_is_configure_phase()
{
    return ngx_http_lua_is_configure_phase();
}


int
ngx_http_lua_ffi_configure_shared_dict(ngx_str_t *name, ngx_str_t *size,
     u_char *errstr, size_t *err_len)
{
    ngx_int_t                     rc;
    ssize_t                       ssize;
    lua_State                    *L;
    ngx_http_lua_main_conf_t     *lmcf;
    ngx_conf_t                   *cf = cfp;
    ngx_shm_zone_t              **zone;

    lmcf = ngx_http_conf_get_module_main_conf(cf, ngx_http_lua_module);

    ssize = ngx_parse_size(size);
    if (ssize <= NGX_HTTP_LUA_SHDICT_MINSIZE) {
        *err_len = ngx_snprintf(errstr, *err_len,
                                "invalid lua shared dict size \"%s\"",
                                size->data)
                   - errstr;
        return NGX_DECLINED;
    }

    rc = ngx_http_lua_shared_dict_add(cf, name, ssize);
    if (rc != NGX_OK) {
        if (rc == NGX_DECLINED) {
            *err_len = ngx_snprintf(errstr, *err_len,
                                    "lua_shared_dict \"%V\" is already defined"
                                    " as \"%V\"", name, name)
                       - errstr;
        }

        return rc;
    }

    zone = lmcf->shdict_zones->elts;

    L = lmcf->lua;

    lua_getglobal(L, "ngx");
    lua_getfield(L, -1, "shared");
    ngx_http_lua_create_shdict_mt(L);

    /* ngx ngx.shared shmt */

    ngx_http_lua_attach_shdict(L, name, zone[lmcf->shdict_zones->nelts - 1]);

    lua_pop(L, 3); /* pop: ngx ngx.shared shmt */

    return NGX_OK;
}


void
ngx_http_lua_ffi_configure_max_pending_timers(int n_timers)
{

    ngx_http_lua_main_conf_t   *lmcf;
    ngx_conf_t                 *cf = cfp;

    lmcf = ngx_http_conf_get_module_main_conf(cf, ngx_http_lua_module);

    lmcf->max_pending_timers = (ngx_int_t) n_timers;
}


void
ngx_http_lua_ffi_configure_max_running_timers(int n_timers)
{

    ngx_http_lua_main_conf_t   *lmcf;
    ngx_conf_t                 *cf = cfp;

    lmcf = ngx_http_conf_get_module_main_conf(cf, ngx_http_lua_module);

    lmcf->max_running_timers = (ngx_int_t) n_timers;
}


int
ngx_http_lua_ffi_configure_env(u_char *value, size_t name_len, size_t len)
{
    ngx_core_conf_t            *ccf;
    ngx_str_t                  *var;
    ngx_conf_t                 *cf = cfp;

    ccf = (ngx_core_conf_t *) ngx_get_conf(cf->cycle->conf_ctx,
                                           ngx_core_module);

    var = ngx_array_push(&ccf->env);
    if (var == NULL) {
        return NGX_ERROR;
    }

    var->data = ngx_pnalloc(cf->pool, len);
    if (var->data == NULL) {
        return NGX_ERROR;
    }

    (void) ngx_copy(var->data, value, len);
    var->len = name_len;

    return NGX_OK;
}
#endif


/* vi:set ft=c ts=4 sw=4 et fdm=marker: */
