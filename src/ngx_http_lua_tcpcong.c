/*
 * Copyright (C) Rain Li (blacktear23)
 *
 */

#ifndef DDEBUG
#define DDEBUG 0
#endif
#include "ddebug.h"


#include "ngx_http_lua_tcpcong.h"
#include "ngx_http_lua_util.h"
#include "ngx_http_lua_api.h"


int ngx_socket_set_tcp_congestion(ngx_socket_t s, const char* cong_name);
static int ngx_http_lua_ngx_set_tcp_congestion(lua_State *L);


#if (NGX_LINUX)

int
ngx_socket_set_tcp_congestion(ngx_socket_t s, const char* cong_name) {
    u_char optval[16];
    ngx_cpystrn(optval, (char *)cong_name, 15);
    return setsockopt(s, IPPROTO_TCP, TCP_CONGESTION,
                      (void *)optval, strlen((char *)optval));
}

#else

int
ngx_socket_set_tcp_congestion(ngx_socket_t s, const char* cong_name) {
    return 0;
}

#endif

/**
 * Set TCP Congestion
 * */
static int
ngx_http_lua_ngx_set_tcp_congestion(lua_State *L)
{
    ngx_http_request_t  *r;
    int                 nargs;
    int                 type;
    int                 ret;
    size_t              len;
    const char          *p;

    r = ngx_http_lua_get_request(L);
    if (r == NULL) {
        return luaL_error(L, "no request object found");
    }

    nargs = lua_gettop(L);
    if (nargs != 1) {
        return luaL_error(L, "attempt to pass %d arguments, bug accepted 1",
                          nargs);
    }
    type = lua_type(L, 1);
    if (type != LUA_TSTRING) {
        return luaL_error(L, "require string parameter");
    }
    p = lua_tolstring(L, 1, &len);
    ret = ngx_socket_set_tcp_congestion(r->connection->fd, p);
    if (ret < 0) {
        ngx_log_error(NGX_LOG_WARN, r->connection->log, 0,
                      "set tcp congestion %s failed: %d", p, ret);
    }
    return 1;
}

void
ngx_http_lua_inject_req_tcp_congestion_api(lua_State *L)
{
    lua_pushcfunction(L, ngx_http_lua_ngx_set_tcp_congestion);
    lua_setfield(L, -2, "set_cong");
}
