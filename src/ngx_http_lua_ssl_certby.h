
/*
 * Copyright (C) Yichun Zhang (agentzh)
 */


#ifndef _NGX_HTTP_LUA_SSL_CERTBY_H_INCLUDED_
#define _NGX_HTTP_LUA_SSL_CERTBY_H_INCLUDED_


#include "ngx_http_lua_common.h"


#if (NGX_HTTP_SSL)


ngx_int_t ngx_http_lua_ssl_cert_handler_inline(ngx_http_request_t *r,
    ngx_http_lua_srv_conf_t *lscf, lua_State *L);

ngx_int_t ngx_http_lua_ssl_cert_handler_file(ngx_http_request_t *r,
    ngx_http_lua_srv_conf_t *lscf, lua_State *L);

char *ngx_http_lua_ssl_cert_by_lua_block(ngx_conf_t *cf, ngx_command_t *cmd,
    void *conf);

char *ngx_http_lua_ssl_cert_by_lua(ngx_conf_t *cf, ngx_command_t *cmd,
    void *conf);

int ngx_http_lua_ssl_cert_handler(ngx_ssl_conn_t *ssl_conn, void *data);

#ifdef TLSEXT_TYPE_application_layer_protocol_negotiation
int ngx_http_lua_ssl_alpn_select(ngx_ssl_conn_t *ssl_conn,
    const unsigned char **out, unsigned char *outlen,
    const unsigned char *in, unsigned int inlen, void *arg);
#endif

#ifdef TLSEXT_TYPE_next_proto_neg
int ngx_http_lua_ssl_npn_advertised(ngx_ssl_conn_t *ssl_conn,
    const unsigned char **out, unsigned int *outlen, void *arg);
#endif

#endif  /* NGX_HTTP_SSL */


#endif /* _NGX_HTTP_LUA_SSL_CERTBY_H_INCLUDED_ */

/* vi:set ft=c ts=4 sw=4 et fdm=marker: */
