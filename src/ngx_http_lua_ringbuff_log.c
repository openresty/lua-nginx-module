
/*
 * Copyright (C) OpenResty, Inc.
 */


#ifndef DDEBUG
#define DDEBUG 0
#endif
#include "ddebug.h"


#include <nginx.h>
#include "ngx_http_lua_ringbuff_log.h"


typedef struct {
    int    is_data;
    int    log_level;             /* attatch info */
    size_t len;                   /* data length */
}ringbuff_head;


static void * log_rb_head(ngx_http_lua_log_ringbuff_t *rb);
static void log_rb_set_tail(ngx_http_lua_log_ringbuff_t *rb, int is_data,
    int log_level, void *buf, int n);
static size_t log_rb_rleft(ngx_http_lua_log_ringbuff_t *rb);


void
log_rb_init(ngx_http_lua_log_ringbuff_t *rb, void *buf, size_t len)
{
    rb->data = buf;
    rb->size = len;

    rb->tail = rb->data;
    rb->head = rb->data;
    rb->count = 0;

    return;
}


void
log_rb_reset(ngx_http_lua_log_ringbuff_t *rb)
{
    rb->tail = rb->data;
    rb->head = rb->data;
    rb->count = 0;

    return;
}


static void *
log_rb_head(ngx_http_lua_log_ringbuff_t *rb)
{
    ringbuff_head       *head;

    /* useless data */
    if (rb->size - (rb->head - rb->data) < sizeof(ringbuff_head)) {
        rb->head = rb->data;
        return rb->head;
    }

    /* placehold data */
    head = (ringbuff_head *)rb->head;
    if (!head->is_data) {
        rb->head = rb->data;
        return rb->head;
    }

    return rb->head;
}


static void
log_rb_set_tail(ngx_http_lua_log_ringbuff_t *rb, int is_data,
    int log_level, void *buf, int n)
{
    ringbuff_head        *head;

    head = (ringbuff_head *) rb->tail;
    head->len = n;
    head->log_level = log_level;
    head->is_data = is_data;

    if (!is_data) {
        rb->tail = rb->data;
        return;
    }

    rb->tail += sizeof(ringbuff_head);
    memcpy(rb->tail, buf, n);
    rb->tail += n;
    rb->count += 1;

    return;
}


static size_t
log_rb_rleft(ngx_http_lua_log_ringbuff_t *rb)
{
    if (rb->tail >= rb->head) {
        return rb->data + rb->size - rb->tail;
    }

    return rb->head - rb->tail;
}


ngx_int_t
log_rb_write(ngx_http_lua_log_ringbuff_t *rb, int log_level,
    void *buf, size_t n)
{
    size_t               rleft, head_len;
    ringbuff_head       *head;

    head_len = sizeof(ringbuff_head);

    if (n + head_len > rb->size) {
        return NGX_ERROR;
    }

    rleft = log_rb_rleft(rb);

    if (rleft < n + head_len) {
        log_rb_set_tail(rb, 0, 0, 0, 0);    /*  set placehold */

        rb->tail = rb->data;

        do {                                /*  thrown old data */
            if (rb->head != log_rb_head(rb)) {
                break;
            }

            head = (ringbuff_head *)rb->head;
            rb->head += head_len + head->len;
            rb->count--;

            log_rb_head(rb);
            rleft = log_rb_rleft(rb);
        } while (rleft < n + head_len);
    }

    log_rb_set_tail(rb, 1, log_level, buf, n);

    return NGX_OK;
}


ngx_int_t
log_rb_read(ngx_http_lua_log_ringbuff_t *rb, void **buf, size_t *n)
{
    ringbuff_head       *head;

    if (rb->count == 0) {
        return NGX_ERROR;
    }

    head = (ringbuff_head *)log_rb_head(rb);

    if (!head->is_data) {
        return NGX_ERROR;
    }

    *n = head->len;
    rb->head += sizeof(ringbuff_head);
    *buf = rb->head;
    rb->head += head->len;
    rb->count--;

    if (rb->count == 0) {
        log_rb_reset(rb);
    }

    return NGX_OK;
}
