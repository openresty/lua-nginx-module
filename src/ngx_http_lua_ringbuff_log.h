
/*
 * Copyright (C) OpenResty, Inc.
 */


#ifndef _NGX_HTTP_LUA_RINGBUFF_LOG_H_INCLUDED_
#define _NGX_HTTP_LUA_RINGBUFF_LOG_H_INCLUDED_


#include <nginx.h>
#include <ngx_core.h>


typedef struct {
    char      *tail;              /*  write point     */
    char      *head;              /*  read point      */
    char      *data;              /*  log buffer      */
    size_t     size;              /*  buffer size     */
    size_t     count;             /*  count           */
}ngx_http_lua_log_ringbuff_t;


void log_rb_init(ngx_http_lua_log_ringbuff_t *rb, void *buf, size_t len);
void log_rb_reset(ngx_http_lua_log_ringbuff_t *rb);
ngx_int_t log_rb_read(ngx_http_lua_log_ringbuff_t *rb, void **buf, size_t *n);
ngx_int_t log_rb_write(ngx_http_lua_log_ringbuff_t *rb, int log_level,
    void *buf, size_t n);


#endif /* _NGX_HTTP_LUA_RINGBUFF_LOG_H_INCLUDED_ */

/* vi:set ft=c ts=4 sw=4 et fdm=marker: */
