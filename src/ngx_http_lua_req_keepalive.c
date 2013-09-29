
/*
 * Copyright (C) Yichun Zhang (agentzh)
 */


#ifndef DDEBUG
#define DDEBUG 0
#endif


#include "ddebug.h"
#include "ngx_http_lua_req_keepalive.h"
#include "ngx_http_lua_util.h"


static int ngx_http_lua_ngx_req_get_keepalive(lua_State *L);
static int ngx_http_lua_ngx_req_set_keepalive(lua_State *L);


void
ngx_http_lua_inject_req_keepalive_api(lua_State *L)
{
    lua_pushcfunction(L, ngx_http_lua_ngx_req_get_keepalive);
    lua_setfield(L, -2, "get_keepalive");

    lua_pushcfunction(L, ngx_http_lua_ngx_req_set_keepalive);
    lua_setfield(L, -2, "set_keepalive");
}


static int
ngx_http_lua_ngx_req_get_keepalive(lua_State *L)
{
    int                      n;
    ngx_http_request_t      *r;

    n = lua_gettop(L);
    if (n != 0) {
        return luaL_error(L, "no arguments expected but got %d", n);
    }

    r = ngx_http_lua_get_req(L);
    if (r == NULL) {
        return luaL_error(L, "request object not found");
    }

    ngx_http_lua_check_fake_request(L, r);

    lua_pushboolean(L, r->keepalive);
    return 1;
}


static int
ngx_http_lua_ngx_req_set_keepalive(lua_State *L)
{
    int                      n;
    ngx_http_request_t      *r;
    int                      keepalive;

    n = lua_gettop(L);
    if (n != 1) {
        return luaL_error(L, "only one argument expected but got %d", n);
    }

    keepalive = lua_toboolean(L, 1);

    r = ngx_http_lua_get_req(L);
    if (r == NULL) {
        return luaL_error(L, "request object not found");
    }

    ngx_http_lua_check_fake_request(L, r);

    r->keepalive = keepalive;
    
    return 1;
}
