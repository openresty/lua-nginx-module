
/*
 * Copyright (C) Xiaozhe Wang (chaoslawful)
 * Copyright (C) Yichun Zhang (agentzh)
 */


#ifndef _NGX_HTTP_LUA_HEADERS_IN_H_INCLUDED_
#define _NGX_HTTP_LUA_HEADERS_IN_H_INCLUDED_


#include <nginx.h>
#include "ngx_http_lua_common.h"


ngx_int_t ngx_http_lua_set_input_header(ngx_http_request_t *r, ngx_str_t key,
    ngx_str_t value, unsigned override);

ngx_int_t ngx_http_lua_init_builtin_headers_in(ngx_conf_t *cf,
    ngx_http_lua_main_conf_t *lmcf);

#endif /* _NGX_HTTP_LUA_HEADERS_IN_H_INCLUDED_ */

/* vi:set ft=c ts=4 sw=4 et fdm=marker: */
