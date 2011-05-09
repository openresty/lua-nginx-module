/* vim:set ft=c ts=4 sw=4 et fdm=marker: */
#ifndef NGX_HTTP_LUA_HEADERS_OUT_H
#define NGX_HTTP_LUA_HEADERS_OUT_H


#include <nginx.h>
#include "ngx_http_lua_common.h"


ngx_int_t ngx_http_lua_set_output_header(ngx_http_request_t *r, ngx_str_t key,
        ngx_str_t value, ngx_flag_t override);


#endif /* NGX_HTTP_LUA_HEADERS_OUT_H */

