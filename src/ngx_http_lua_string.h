
/*
 * Copyright (C) Xiaozhe Wang (chaoslawful)
 * Copyright (C) Yichun Zhang (agentzh)
 */


#ifndef _NGX_HTTP_LUA_STRING_H_INCLUDED_
#define _NGX_HTTP_LUA_STRING_H_INCLUDED_


#include "ngx_http_lua_common.h"


void ngx_http_lua_inject_string_api(lua_State *L);


#ifndef NGX_LUA_NO_FFI_API
#include "ngx_http_lua_util.h"

int ngx_http_lua_ffi_decode_args_helper(u_char *args, size_t len,
    ngx_http_lua_ffi_table_elt_t *out, int count);
#endif


#endif /* _NGX_HTTP_LUA_STRING_H_INCLUDED_ */


/* vi:set ft=c ts=4 sw=4 et fdm=marker: */
