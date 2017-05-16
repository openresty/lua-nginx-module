
/*
 * Copyright (C) Yichun Zhang (agentzh)
 */


#ifndef DDEBUG
#define DDEBUG 0
#endif

#include "ddebug.h"
#include "ngx_http_lua_initby.h"
#include "ngx_http_lua_util.h"


ngx_int_t
ngx_http_lua_init_by_inline(ngx_log_t *log, ngx_http_lua_main_conf_t *lmcf,
    lua_State *L)
{
    int         status;

    status = luaL_loadbuffer(L, (char *) lmcf->init_src.data,
                             lmcf->init_src.len, "=init_by_lua")
             || ngx_http_lua_do_call(log, L);

    return ngx_http_lua_report(log, L, status, "init_by_lua");
}


ngx_int_t
ngx_http_lua_init_by_file(ngx_log_t *log, ngx_http_lua_main_conf_t *lmcf,
    lua_State *L)
{
    int         status;

    status = luaL_loadfile(L, (char *) lmcf->init_src.data)
             || ngx_http_lua_do_call(log, L);

    return ngx_http_lua_report(log, L, status, "init_by_lua_file");
}


ngx_int_t
ngx_http_lua_init_callback(ngx_cycle_t *cycle, void *data)
{
    ngx_http_lua_main_conf_t    *lmcf;
    volatile ngx_cycle_t        *saved_cycle;
    ngx_int_t                    rc;

    lmcf = (ngx_http_lua_main_conf_t *) data;

    if (!lmcf) {
        return NGX_ERROR;
    }

    if (lmcf->init_handler) {
        saved_cycle = ngx_cycle;
        ngx_cycle = cycle;

        rc = lmcf->init_handler(cycle->log, lmcf, lmcf->lua);

        ngx_cycle = saved_cycle;

        if (rc != NGX_OK) {
            return NGX_ERROR;
        }
    }

    return NGX_OK;
}

/* vi:set ft=c ts=4 sw=4 et fdm=marker: */
