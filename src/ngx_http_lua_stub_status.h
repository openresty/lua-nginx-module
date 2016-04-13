#ifndef _NGX_HTTP_LUA_STUB_STATUS_H_INCLUDED_
#define _NGX_HTTP_LUA_STUB_STATUS_H_INCLUDED_

#if (NGX_STAT_STUB)

#include "ngx_http_lua_common.h"


extern ngx_atomic_t  *ngx_stat_accepted;
extern ngx_atomic_t  *ngx_stat_handled;
extern ngx_atomic_t  *ngx_stat_requests;
extern ngx_atomic_t  *ngx_stat_active;
extern ngx_atomic_t  *ngx_stat_reading;
extern ngx_atomic_t  *ngx_stat_writing;
extern ngx_atomic_t  *ngx_stat_waiting;


void ngx_http_lua_inject_stub_status_api(lua_State *L);

#endif

#endif /* _NGX_HTTP_LUA_STUB_STATUS_H_INCLUDED_ */
