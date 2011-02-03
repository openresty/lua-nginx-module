/* vim:set ft=c ts=4 sw=4 et fdm=marker: */
#ifndef NGX_HTTP_LUA_HOOK_H
#define NGX_HTTP_LUA_HOOK_H

#include "ngx_http_lua_common.h"

#define NGX_LUA_EXCEPTION_TRY if (setjmp(ngx_http_lua_exception) == 0)
#define NGX_LUA_EXCEPTION_CATCH else
#define NGX_LUA_EXCEPTION_THROW(x) longjmp(ngx_http_lua_exception, (x))

jmp_buf ngx_http_lua_exception;

int ngx_http_lua_atpanic(lua_State *L);
int ngx_http_lua_print(lua_State *L);

int ngx_http_lua_ngx_send_headers(lua_State *L);

int ngx_http_lua_ngx_say(lua_State *L);
int ngx_http_lua_ngx_print(lua_State *L);
int ngx_http_lua_ngx_log(lua_State *L);

int ngx_http_lua_ngx_exit(lua_State *L);

int ngx_http_lua_ngx_flush(lua_State *L);
int ngx_http_lua_ngx_eof(lua_State *L);

int ngx_http_lua_ngx_escape_uri(lua_State *L);
int ngx_http_lua_ngx_unescape_uri(lua_State *L);

int ngx_http_lua_ngx_quote_sql_str(lua_State *L);

int ngx_http_lua_ngx_md5(lua_State *L);
int ngx_http_lua_ngx_md5_bin(lua_State *L);

int ngx_http_lua_ngx_decode_base64(lua_State *L);
int ngx_http_lua_ngx_encode_base64(lua_State *L);

int ngx_http_lua_ngx_today(lua_State *L);
int ngx_http_lua_ngx_time(lua_State *L);
int ngx_http_lua_ngx_localtime(lua_State *L);
int ngx_http_lua_ngx_utctime(lua_State *L);
int ngx_http_lua_ngx_cookie_time(lua_State *L);
int ngx_http_lua_ngx_redirect(lua_State *L);

int ngx_http_lua_ngx_location_capture(lua_State *L);
int ngx_http_lua_ngx_location_capture_multi(lua_State *L);

int ngx_http_lua_ngx_get(lua_State *L);
int ngx_http_lua_ngx_set(lua_State *L);

int ngx_http_lua_header_get(lua_State *L);
int ngx_http_lua_header_set(lua_State *L);

int ngx_http_lua_ngx_exec(lua_State *L);

int ngx_http_lua_ndk_set_var_get(lua_State *L);
int ngx_http_lua_ndk_set_var_set(lua_State *L);

int ngx_http_lua_run_set_var_directive(lua_State *L);


#endif /* NGX_HTTP_LUA_HOOK_H */

