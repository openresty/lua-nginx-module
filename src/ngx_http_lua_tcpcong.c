#ifndef DDEBUG
#define DDEBUG 0
#endif
#include "ddebug.h"


#include "ngx_http_lua_tcpcong.h"
#include "ngx_http_lua_util.h"
#include "ngx_http_lua_api.h"


int ngx_socket_set_tcp_congestion(ngx_socket_t s,
    const char *cong_name, size_t cong_name_len);
static int ngx_http_lua_ngx_set_tcp_congestion(lua_State *L);


#if (NGX_LINUX)


int
ngx_socket_set_tcp_congestion(ngx_socket_t s,
    const char *cong_name, size_t cong_name_len)
{
    return setsockopt(s, IPPROTO_TCP, TCP_CONGESTION,
                      (void *) cong_name, (socklen_t) cong_name_len);
}


#else


int
ngx_socket_set_tcp_congestion(ngx_socket_t s,
    const char *cong_name, size_t cong_name_len)
{
    return EOSNOTSUPPORT;
}


#endif


/**
 * Set TCP Congestion
 * */
static int
ngx_http_lua_ngx_set_tcp_congestion(lua_State *L)
{
    ngx_http_request_t  *r;
    int                  nargs;
    int                  type;
    int                  ret;
    size_t               len;
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
    if (len > 16) {
        return luaL_error(L,
                          "TCP congestion control algorithm name too large, "
                          "no more than 16 character");
    }

    ret = ngx_socket_set_tcp_congestion(r->connection->fd, p, len);
    if (ret < 0) {
        if (ret == EOSNOTSUPPORT) {
            return luaL_error(L, "OS not support");
        } else {
            return luaL_error(L, "set TCP congestion control algorithm failed");
        }
    }

    return 1;
}


void
ngx_http_lua_inject_req_tcp_congestion_api(lua_State *L)
{
    lua_pushcfunction(L, ngx_http_lua_ngx_set_tcp_congestion);
    lua_setfield(L, -2, "set_cong");
}

/* vi:set ft=c ts=4 sw=4 et fdm=marker: */
