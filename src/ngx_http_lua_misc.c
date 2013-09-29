
/*
 * Copyright (C) Xiaozhe Wang (chaoslawful)
 * Copyright (C) Yichun Zhang (agentzh)
 */


#ifndef DDEBUG
#define DDEBUG 0
#endif
#include "ddebug.h"


#include "ngx_http_lua_misc.h"
#include "ngx_http_lua_ctx.h"
#include "ngx_http_lua_util.h"


static int ngx_http_lua_ngx_get(lua_State *L);
static int ngx_http_lua_ngx_set(lua_State *L);


void
ngx_http_lua_inject_misc_api(lua_State *L)
{
    /* ngx. getter and setter */
    lua_createtable(L, 0, 2); /* metatable for .ngx */
    lua_pushcfunction(L, ngx_http_lua_ngx_get);
    lua_setfield(L, -2, "__index");
    lua_pushcfunction(L, ngx_http_lua_ngx_set);
    lua_setfield(L, -2, "__newindex");
    lua_setmetatable(L, -2);
}


static int
ngx_http_lua_ngx_get(lua_State *L)
{
    ngx_http_request_t          *r;
    u_char                      *p;
    size_t                       len;
    ngx_http_lua_ctx_t          *ctx;

    r = ngx_http_lua_get_req(L);
    if (r == NULL) {
        return luaL_error(L, "no request object found");
    }

    p = (u_char *) luaL_checklstring(L, -1, &len);

    dd("ngx get %s", p);

    if (len == sizeof("status") - 1
        && ngx_strncmp(p, "status", sizeof("status") - 1) == 0)
    {
        ngx_http_lua_check_fake_request(L, r);
        lua_pushnumber(L, (lua_Number) r->headers_out.status);
        return 1;
    }

    if (len == sizeof("ctx") - 1
        && ngx_strncmp(p, "ctx", sizeof("ctx") - 1) == 0)
    {
        return ngx_http_lua_ngx_get_ctx(L);
    }

    if (len == sizeof("is_subrequest") - 1
        && ngx_strncmp(p, "is_subrequest", sizeof("is_subrequest") - 1) == 0)
    {
        lua_pushboolean(L, r != r->main);
        return 1;
    }

    if (len == sizeof("headers_sent") - 1
        && ngx_strncmp(p, "headers_sent", sizeof("headers_sent") - 1) == 0)
    {
        ctx = ngx_http_get_module_ctx(r, ngx_http_lua_module);
        if (ctx == NULL) {
            return luaL_error(L, "no ctx");
        }

        ngx_http_lua_check_fake_request2(L, r, ctx);

        dd("headers sent: %d", r->header_sent);

        lua_pushboolean(L, r->header_sent ? 1 : 0);
        return 1;
    }

    dd("key %s not matched", p);

    lua_pushnil(L);
    return 1;
}


static int
ngx_http_lua_ngx_set(lua_State *L)
{
    ngx_http_request_t          *r;
    u_char                      *p;
    size_t                       len;
    ngx_http_lua_ctx_t          *ctx;

    /* we skip the first argument that is the table */
    p = (u_char *) luaL_checklstring(L, 2, &len);

    if (len == sizeof("status") - 1
        && ngx_strncmp(p, "status", sizeof("status") - 1) == 0)
    {
        r = ngx_http_lua_get_req(L);
        if (r == NULL) {
            return luaL_error(L, "no request object found");
        }

        ctx = ngx_http_get_module_ctx(r, ngx_http_lua_module);

        if (r->header_sent) {
            ngx_log_error(NGX_LOG_ERR, r->connection->log, 0,
                          "attempt to set ngx.status after sending out "
                          "response headers");
            return 0;
        }

        ngx_http_lua_check_fake_request2(L, r, ctx);

        /* get the value */
        r->headers_out.status = (ngx_uint_t) luaL_checknumber(L, 3);

        if (r->headers_out.status == 101) {
            /*
             * XXX work-around a bug in the Nginx core that 101 does
             * not have a default status line
             */

            ngx_str_set(&r->headers_out.status_line, "101 Switching Protocols");

        } else {
            r->headers_out.status_line.len = 0;
        }

        return 0;
    }

    if (len == sizeof("ctx") - 1
        && ngx_strncmp(p, "ctx", sizeof("ctx") - 1) == 0)
    {
        r = ngx_http_lua_get_req(L);
        if (r == NULL) {
            return luaL_error(L, "no request object found");
        }

        return ngx_http_lua_ngx_set_ctx(L);
    }

    lua_rawset(L, -3);
    return 0;
}

/* vi:set ft=c ts=4 sw=4 et fdm=marker: */
