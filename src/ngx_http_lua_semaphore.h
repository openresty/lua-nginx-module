
/*
 * Copyright (C) cuiweixie
 */


#ifndef _NGX_HTTP_LUA_SEMAPHORE_H_INCLUDED_
#define _NGX_HTTP_LUA_SEMAPHORE_H_INCLUDED_


#include "ngx_http_lua_common.h"

typedef struct ngx_http_lua_semaphore_s {
    ngx_queue_t            wait_queue;
    ngx_event_t            sem_event;
    struct ngx_http_lua_semaphore_s *next;
    ngx_log_t             *log;
    int                    count;
    unsigned               in_post_event:1;
    unsigned               wait_count:31;
 } ngx_http_lua_semaphore_t;


int ngx_http_lua_ffi_set_semaphore_threshold(ngx_int_t threshold);
void ngx_http_lua_cleanup_semaphore(void *data);


#endif /* _NGX_HTTP_LUA_SEMAPHORE_H_INCLUDED_ */

