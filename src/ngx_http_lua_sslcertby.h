
/*
 * Copyright (C) Yichun Zhang (agentzh)
 */


#ifndef _NGX_HTTP_LUA_SSLCERTBY_H_INCLUDED_
#define _NGX_HTTP_LUA_SSLCERTBY_H_INCLUDED_


#include "ngx_http_lua_common.h"


typedef struct {
    ngx_connection_t        *connection; /* original true connection */
    ngx_http_request_t      *request;    /* fake request */
    int                      exit_code;  /* exit code for openssl's
                                            set_cert_cb callback */
    unsigned                 done;       /* :1 */
    unsigned                 aborted;    /* :1 */
} ngx_http_lua_ssl_cert_ctx_t;

typedef struct {
	const unsigned char *common_name;
	const unsigned char *country;
	const unsigned char *state;
	const unsigned char *city;
	const unsigned char *organisation;
} csr_info_t;

ngx_int_t ngx_http_lua_ssl_cert_handler_inline(ngx_http_request_t *r,
    ngx_http_lua_srv_conf_t *lscf, lua_State *L);

ngx_int_t ngx_http_lua_ssl_cert_handler_file(ngx_http_request_t *r,
    ngx_http_lua_srv_conf_t *lscf, lua_State *L);

char *ngx_http_lua_ssl_cert_by_lua(ngx_conf_t *cf, ngx_command_t *cmd,
    void *conf);

int ngx_http_lua_ssl_cert_handler(ngx_ssl_conn_t *ssl_conn, void *data);


#endif /* _NGX_HTTP_LUA_SSLCERTBY_H_INCLUDED_ */

/* vi:set ft=c ts=4 sw=4 et fdm=marker: */
