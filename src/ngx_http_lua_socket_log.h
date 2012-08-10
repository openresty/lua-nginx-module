#ifndef NGX_HTTP_LUA_SOCKET_LOG_H
#define NGX_HTTP_LUA_SOCKET_LOG_H


#include "ngx_http_lua_common.h"

void ngx_http_lua_socket_log_error(ngx_uint_t level, ngx_http_request_t *r,
                                   ngx_err_t err, const char *fmt, ...);

#endif /* NGX_HTTP_LUA_SOCKET_LOG_H */

