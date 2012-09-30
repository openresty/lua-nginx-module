#ifndef NGX_HTTP_LUA_UTHREAD_H
#define NGX_HTTP_LUA_UTHREAD_H


#include "ngx_http_lua_common.h"


#define ngx_http_lua_is_thread(ctx)                                          \
    ((ctx)->cur_co_ctx->is_uthread || (ctx)->cur_co_ctx == &(ctx)->entry_co_ctx)


#define ngx_http_lua_is_entry_thread(ctx)                                    \
    ((ctx)->cur_co_ctx == &(ctx)->entry_co_ctx)


#define ngx_http_lua_entry_thread_alive(ctx)                                 \
    ((ctx)->entry_co_ctx.co_ref != LUA_NOREF)


#define ngx_http_lua_coroutine_alive(coctx)                                  \
    ((coctx)->co_status != NGX_HTTP_LUA_CO_DEAD                              \
     && (coctx)->co_status != NGX_HTTP_LUA_CO_ZOMBIE)


void ngx_http_lua_inject_uthread_api(ngx_log_t *log, lua_State *L);


#endif /* NGX_HTTP_LUA_UTHREAD_H */

