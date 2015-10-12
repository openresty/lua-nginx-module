
/*
 * Copyright (C) Yichun Zhang (agentzh)
 */


#ifndef DDEBUG
#define DDEBUG 0
#endif
#include "ddebug.h"


#include "ngx_http_lua_worker.h"


static int ngx_http_lua_ngx_worker_exiting(lua_State *L);
static int ngx_http_lua_ngx_worker_pid(lua_State *L);
static int ngx_http_lua_ngx_worker_count(lua_State *L);


void
ngx_http_lua_inject_worker_api(lua_State *L)
{
    lua_createtable(L, 0 /* narr */, 3 /* nrec */);    /* ngx.worker. */

    lua_pushcfunction(L, ngx_http_lua_ngx_worker_exiting);
    lua_setfield(L, -2, "exiting");

    lua_pushcfunction(L, ngx_http_lua_ngx_worker_pid);
    lua_setfield(L, -2, "pid");

    lua_pushcfunction(L, ngx_http_lua_ngx_worker_count);
    lua_setfield(L, -2, "count");

    lua_setfield(L, -2, "worker");
}


static int
ngx_http_lua_ngx_worker_exiting(lua_State *L)
{
    lua_pushboolean(L, ngx_exiting);
    return 1;
}


static int
ngx_http_lua_ngx_worker_pid(lua_State *L)
{
    lua_pushinteger(L, (lua_Integer) ngx_pid);
    return 1;
}


#ifndef NGX_LUA_NO_FFI_API
int
ngx_http_lua_ffi_worker_pid(void)
{
    return (int) ngx_pid;
}


int
ngx_http_lua_ffi_worker_exiting(void)
{
    return (int) ngx_exiting;
}


static int
ngx_http_lua_ngx_worker_count(lua_State *L)
{
    ngx_core_conf_t   *ccf;
    ccf = (ngx_core_conf_t *) ngx_get_conf(ngx_cycle->conf_ctx, ngx_core_module);

    lua_pushinteger(L, ccf->worker_processes);
    return 1;
}
#endif
