
/*
 * Copyright (C) Xiaozhe Wang (chaoslawful)
 * Copyright (C) Yichun Zhang (agentzh)
 */


#ifndef _NGX_HTTP_LUA_TCPCONG_H_INCLUDED_
#define _NGX_HTTP_LUA_TCPCONG_H_INCLUDED_


#include "ngx_http_lua_common.h"


#if (NGX_LINUX)

#ifndef TCP_CONGESTION
#define TCP_CONGESTION 13
#endif

#endif


#define EOSNOTSUPPORT -23


int ngx_socket_set_tcp_congestion(ngx_socket_t s,
    const char *cong_name, size_t cong_name_len);
void ngx_http_lua_inject_req_tcp_congestion_api(lua_State *L);


#endif /* _NGX_HTTP_LUA_TCPCONG_H_INCLUDED_ */

/* vi:set ft=c ts=4 sw=4 et fdm=marker: */
