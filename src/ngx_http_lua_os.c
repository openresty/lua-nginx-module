
/*
 * Copyright (C) Yichun Zhang (agentzh)
 */


#ifndef NGX_LUA_NO_FFI_API


#ifndef DDEBUG
#define DDEBUG 0
#endif
#include "ddebug.h"


#include "ngx_http_lua_util.h"


u_char *ngx_http_lua_ffi_os_getenv(ngx_cycle_t *cycle, ngx_http_request_t *r,
    const char *varname);


u_char *
ngx_http_lua_ffi_os_getenv(ngx_cycle_t *cycle, ngx_http_request_t *r,
    const char *varname)
{
    u_char           *value = NULL;
    ngx_str_t        *var;
    ngx_uint_t        i;
    ngx_core_conf_t  *ccf;

    /* init phase: search from ccf->env */
    if (r == NULL) {
        ccf = (ngx_core_conf_t *) ngx_get_conf(cycle->conf_ctx,
                                               ngx_core_module);
        var = ccf->env.elts;

        for (i = 0; i < ccf->env.nelts; i++) {
            if (var[i].data[var[i].len] == '='
                && ngx_strncmp(var[i].data, varname, var[i].len - 1) == 0)
            {
                value = var[i].data + var[i].len + 1;
                break;
            }
        }

        if (value) {
            return value;
        }
    }

    value = (u_char *) getenv(varname);
    return value;
}


#endif /* NGX_LUA_NO_FFI_API */

/* vi:set ft=c ts=4 sw=4 et fdm=marker: */
