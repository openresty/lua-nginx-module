
/*
 * Copyright (C) cuiweixie
 */


#ifndef _NGX_HTTP_LUA_SEMAPHORE_H_INCLUDED_
#define _NGX_HTTP_LUA_SEMAPHORE_H_INCLUDED_


#include "ngx_http_lua_common.h"

#define ngx_http_lua_sem_dis_api_err(c) \
    ((c) == NGX_HTTP_LUA_CONTEXT_SET ? \
        "api is disable in set_by_lua*"  \
    : (c) == NGX_HTTP_LUA_CONTEXT_REWRITE ? \
    "api is disable in rewrite_by_lua*"     \
    : (c) == NGX_HTTP_LUA_CONTEXT_ACCESS ? \
    "api is disable in access_by_lua*"     \
    : (c) == NGX_HTTP_LUA_CONTEXT_CONTENT ? \
    "api is disable in  content_by_lua*"    \
    : (c) == NGX_HTTP_LUA_CONTEXT_LOG ? \
    "api is disable in log_by_lua*"     \
    : (c) == NGX_HTTP_LUA_CONTEXT_HEADER_FILTER ?\
     "api is disable in header_filter_by_lua*"   \
    : (c) == NGX_HTTP_LUA_CONTEXT_BODY_FILTER ? \
    "api is disable in body_filter_by_lua*"    \
    : (c) == NGX_HTTP_LUA_CONTEXT_TIMER ? \
    "api is disable in ngx.timer"                       \
    : (c) == NGX_HTTP_LUA_CONTEXT_INIT_WORKER ? \
    "api is disable in init_worker_by_lua*"       \
    : "(unknown)")

typedef struct ngx_http_lua_semaphore_s {
    ngx_queue_t wait_queue;
    ngx_event_t sem_event;
    struct ngx_http_lua_semaphore_s *next;
    ngx_log_t *log;
    int count;
    unsigned in_post_event:1;
    unsigned wait_count:31;
 }ngx_http_lua_semaphore_t;

#define NGX_HTTP_LUA_SEM_WAIT_TIMEOUT 1
#define NGX_HTTP_LUA_SEM_WAIT_SUCC    0
int ngx_http_lua_ffi_set_semaphore_threshold(ngx_int_t threshold);
void ngx_http_lua_cleanup_sem(void *data);
#endif /* _NGX_HTTP_LUA_SEMAPHORE_H_INCLUDED_ */

