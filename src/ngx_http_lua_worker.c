
/*
 * Copyright (C) Yichun Zhang (agentzh)
 */


#ifndef DDEBUG
#define DDEBUG 0
#endif
#include "ddebug.h"


#define NGX_PROCESS_PRIVILEGED_AGENT    99


int
ngx_http_lua_ffi_worker_pid(void)
{
    return (int) ngx_pid;
}


int
ngx_http_lua_ffi_worker_id(void)
{
#if (nginx_version >= 1009001)
    if (ngx_process != NGX_PROCESS_WORKER
        && ngx_process != NGX_PROCESS_SINGLE)
    {
        return -1;
    }

    return (int) ngx_worker;
#else
    return -1;
#endif
}


int
ngx_http_lua_ffi_worker_exiting(void)
{
    return (int) ngx_exiting;
}


int
ngx_http_lua_ffi_worker_count(void)
{
    ngx_core_conf_t   *ccf;

    ccf = (ngx_core_conf_t *) ngx_get_conf(ngx_cycle->conf_ctx,
                                           ngx_core_module);

    return (int) ccf->worker_processes;
}


int
ngx_http_lua_ffi_master_pid(void)
{
#if (nginx_version >= 1013008)
    if (ngx_process == NGX_PROCESS_SINGLE) {
        return (int) ngx_pid;
    }

    return (int) ngx_parent;
#else
    return NGX_ERROR;
#endif
}


int
ngx_http_lua_ffi_get_process_type(void)
{
    ngx_core_conf_t  *ccf;

#if defined(HAVE_PRIVILEGED_PROCESS_PATCH) && !NGX_WIN32
    if (ngx_process == NGX_PROCESS_HELPER) {
        if (ngx_is_privileged_agent) {
            return NGX_PROCESS_PRIVILEGED_AGENT;
        }
    }
#endif

    if (ngx_process == NGX_PROCESS_SINGLE) {
        ccf = (ngx_core_conf_t *) ngx_get_conf(ngx_cycle->conf_ctx,
                                               ngx_core_module);

        if (ccf->master) {
            return NGX_PROCESS_MASTER;
        }
    }

    return ngx_process;
}

#if defined(nginx_version) && nginx_version >= 1019003
int
ngx_http_lua_ffi_enable_privileged_agent(char **err, unsigned int connections)
#else
int
ngx_http_lua_ffi_enable_privileged_agent(char **err)
#endif
{
#ifdef HAVE_PRIVILEGED_PROCESS_PATCH
    ngx_core_conf_t   *ccf;

    ccf = (ngx_core_conf_t *) ngx_get_conf(ngx_cycle->conf_ctx,
                                           ngx_core_module);

    ccf->privileged_agent = 1;
#if defined(nginx_version) && nginx_version >= 1019003
    ccf->privileged_agent_connections = connections;
#endif

    return NGX_OK;

#else
    *err = "missing privileged agent process patch in the nginx core";
    return NGX_ERROR;
#endif
}


void
ngx_http_lua_ffi_process_signal_graceful_exit(void)
{
    ngx_quit = 1;
}


/* vi:set ft=c ts=4 sw=4 et fdm=marker: */
