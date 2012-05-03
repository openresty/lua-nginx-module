#ifndef NGX_HTTP_LUA_LOGBY_H
#define NGX_HTTP_LUA_LOGBY_H


#include "ngx_http_lua_common.h"


ngx_int_t ngx_http_lua_log_handler(ngx_http_request_t *r);
ngx_int_t ngx_http_lua_log_handler_inline(ngx_http_request_t *r);
ngx_int_t ngx_http_lua_log_handler_file(ngx_http_request_t *r);


#endif /* NGX_HTTP_LUA_REWRITEBY_H */
