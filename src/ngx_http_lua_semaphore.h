
/*
 * Copyright (C) cuiweixie
 */


#ifndef _NGX_HTTP_LUA_SEMAPHORE_H_INCLUDED_
#define _NGX_HTTP_LUA_SEMAPHORE_H_INCLUDED_


#include "ngx_http_lua_common.h"


typedef struct ngx_http_lua_semaphore_mm_s ngx_http_lua_semaphore_mm_t;


typedef struct ngx_http_lua_semaphore_mm_block_s {
    ngx_uint_t                    used;
    ngx_http_lua_semaphore_mm_t  *mm;
    ngx_uint_t                    epoch;
} ngx_http_lua_semaphore_mm_block_t;


typedef struct ngx_http_lua_semaphore_mm_s {
    ngx_queue_t                 free_queue;
    ngx_uint_t                  total;
    ngx_uint_t                  used;
    ngx_uint_t                  num_per_block;
    ngx_uint_t                  cur_epoch;
    ngx_http_lua_main_conf_t   *lmcf;
} ngx_http_lua_semaphore_mm_t;


typedef struct ngx_http_lua_semaphore_s {
    ngx_queue_t            wait_queue;
    ngx_queue_t            chain;
    ngx_event_t            sem_event;
    ngx_log_t             *log;
    ngx_http_lua_semaphore_mm_block_t *block;
    int                    count;
    unsigned               in_post_event:1;
    unsigned               wait_count:31;
 } ngx_http_lua_semaphore_t;


void ngx_http_lua_cleanup_semaphore(void *data);


#endif /* _NGX_HTTP_LUA_SEMAPHORE_H_INCLUDED_ */

