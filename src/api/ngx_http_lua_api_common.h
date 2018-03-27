
#ifndef _NGX_HTTP_LUA_API_COMMON_H_INCLUDED_
#define _NGX_HTTP_LUA_API_COMMON_H_INCLUDED_

#include <ngx_core.h>


#ifndef NGX_LUA_NO_FFI_API
typedef struct {
    int          len;
    /* this padding hole on 64-bit systems is expected */
    u_char      *data;
} ngx_http_lua_ffi_str_t;
#endif /* NGX_LUA_NO_FFI_API */


#endif /* _NGX_HTTP_LUA_API_COMMON_H_INCLUDED_ */

/* vi:set ft=c ts=4 sw=4 et fdm=marker: */
