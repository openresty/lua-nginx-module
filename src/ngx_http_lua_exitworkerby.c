
/*
 * Copyright (C) Yichun Zhang (agentzh)
 */


#ifndef DDEBUG
#define DDEBUG 0
#endif
#include "ddebug.h"


#include "ngx_http_lua_exitworkerby.h"
#include "ngx_http_lua_util.h"


void
ngx_http_lua_exit_worker(ngx_cycle_t *cycle)
{
    ngx_http_lua_main_conf_t    *lmcf;

    lmcf = ngx_http_cycle_get_module_main_conf(cycle, ngx_http_lua_module);
    if (lmcf == NULL
        || lmcf->exit_worker_handler == NULL
        || lmcf->lua == NULL)
    {
        return;
    }

    (void) lmcf->exit_worker_handler(cycle->log, lmcf, lmcf->lua);

    return;
}


ngx_int_t
ngx_http_lua_exit_worker_by_inline(ngx_log_t *log,
    ngx_http_lua_main_conf_t *lmcf, lua_State *L)
{
    int         status;

    status = luaL_loadbuffer(L, (char *) lmcf->exit_worker_src.data,
                            lmcf->exit_worker_src.len, "=exit_worker_by_lua")
             || ngx_http_lua_do_call(log, L);

    return ngx_http_lua_report(log, L, status, "exit_worker_by_lua");
}


ngx_int_t
ngx_http_lua_exit_worker_by_file(ngx_log_t *log,
    ngx_http_lua_main_conf_t *lmcf, lua_State *L)
{
    int         status;

    status = luaL_loadfile(L, (char *) lmcf->exit_worker_src.data)
             || ngx_http_lua_do_call(log, L);

    return ngx_http_lua_report(log, L, status, "exit_worker_by_file");
}
