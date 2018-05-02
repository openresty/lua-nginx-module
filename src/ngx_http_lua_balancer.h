
/*
 * Copyright (C) Yichun Zhang (agentzh)
 */


#ifndef _NGX_HTTP_LUA_BALANCER_H_INCLUDED_
#define _NGX_HTTP_LUA_BALANCER_H_INCLUDED_


#include "ngx_http_lua_common.h"

struct ngx_http_lua_balancer_peer_data_s {
    /* the round robin data must be first */
    ngx_http_upstream_rr_peer_data_t rrp;

    ngx_http_lua_srv_conf_t *conf;
    ngx_http_request_t *request;

    ngx_uint_t more_tries;
    ngx_uint_t total_tries;

    struct sockaddr *sockaddr;
    socklen_t socklen;

    ngx_str_t *host;
    in_port_t port;

    int last_peer_state;

#if !(HAVE_NGX_UPSTREAM_TIMEOUT_FIELDS)
    unsigned cloned_upstream_conf; /* :1 */
#endif
};

ngx_int_t ngx_http_lua_balancer_handler_inline(ngx_http_request_t *r,
    ngx_http_lua_srv_conf_t *lscf, lua_State *L);

ngx_int_t ngx_http_lua_balancer_handler_file(ngx_http_request_t *r,
    ngx_http_lua_srv_conf_t *lscf, lua_State *L);

char *ngx_http_lua_balancer_by_lua(ngx_conf_t *cf, ngx_command_t *cmd,
    void *conf);

char *ngx_http_lua_balancer_by_lua_block(ngx_conf_t *cf, ngx_command_t *cmd,
    void *conf);


#endif /* _NGX_HTTP_LUA_BALANCER_H_INCLUDED_ */
