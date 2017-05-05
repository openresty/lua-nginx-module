
#ifndef DDEBUG
#define DDEBUG 0
#endif
#include "ddebug.h"


#include "ngx_http_lua_common.h"
#include "ngx_http_lua_log_ringbuf.h"


typedef struct {
    unsigned    len:28;     /* :24 is big enough if the max log size is 4k */
    unsigned    log_level:4;
} ngx_http_lua_log_ringbuf_header_t;


enum {
    HEADER_LEN = sizeof(ngx_http_lua_log_ringbuf_header_t)
};


static void *ngx_http_lua_log_ringbuf_next_header(
    ngx_http_lua_log_ringbuf_t *rb);
static void ngx_http_lua_log_ringbuf_append(
    ngx_http_lua_log_ringbuf_t *rb, int sentinel, int log_level, void *buf,
    int n);
static size_t ngx_http_lua_log_ringbuf_free_spaces(
    ngx_http_lua_log_ringbuf_t *rb);


void
ngx_http_lua_log_ringbuf_init(ngx_http_lua_log_ringbuf_t *rb, void *buf,
    size_t len)
{
    rb->data = buf;
    rb->size = len;

    rb->tail = rb->data;
    rb->head = rb->data;
    rb->sentinel = rb->data + rb->size;
    rb->count = 0;
    rb->filter_level = NGX_LOG_DEBUG;

    return;
}


void
ngx_http_lua_log_ringbuf_reset(ngx_http_lua_log_ringbuf_t *rb)
{
    rb->tail = rb->data;
    rb->head = rb->data;
    rb->sentinel = rb->data + rb->size;
    rb->count = 0;

    return;
}


/*
 * get the next data header, it'll skip the useless data space or
 * placehold data
 */
static void *
ngx_http_lua_log_ringbuf_next_header(ngx_http_lua_log_ringbuf_t *rb)
{
    /* useless data */
    if (rb->size - (rb->head - rb->data) < HEADER_LEN)
    {
        rb->head = rb->data;
        return rb->head;
    }

    /* placehold data */
    if (rb->head >= rb->sentinel) {
        rb->head = rb->data;
        return rb->head;
    }

    return rb->head;
}


/* append data to ring buffer directly */
static void
ngx_http_lua_log_ringbuf_append(ngx_http_lua_log_ringbuf_t *rb,
    int sentinel, int log_level, void *buf, int n)
{
    ngx_http_lua_log_ringbuf_header_t        *head;

    if (sentinel) {
        rb->sentinel = rb->tail;
        rb->tail = rb->data;
        return;
    }

    head = (ngx_http_lua_log_ringbuf_header_t *) rb->tail;
    head->len = n;
    head->log_level = log_level;

    rb->tail += HEADER_LEN;
    ngx_memcpy(rb->tail, buf, n);
    rb->tail += n;
    rb->count++;

    return;
}


/* size of free spaces */
static size_t
ngx_http_lua_log_ringbuf_free_spaces(ngx_http_lua_log_ringbuf_t *rb)
{
    if (rb->tail == rb->head && rb->tail == rb->data) {
        return rb->size;
    }

    if (rb->tail > rb->head) {
        return rb->data + rb->size - rb->tail;
    }

    return rb->head - rb->tail;
}


/*
 * try to write log data to ring buffer, throw away old data
 * if there was not enough free spaces.
 */
ngx_int_t
ngx_http_lua_log_ringbuf_write(ngx_http_lua_log_ringbuf_t *rb, int log_level,
    void *buf, size_t n)
{
    size_t              free_spaces;

    ngx_http_lua_log_ringbuf_header_t       *head;

    if (n + HEADER_LEN > rb->size) {
        return NGX_ERROR;
    }

    free_spaces = ngx_http_lua_log_ringbuf_free_spaces(rb);

    if (free_spaces < n + HEADER_LEN) {
        /* if the right space is not enough, mark it as placehold data */
        if ((size_t)(rb->data + rb->size - rb->tail) < n + HEADER_LEN) {
            ngx_http_lua_log_ringbuf_append(rb, 1, 0, NULL, 0);
        }

        do {    /*  throw away old data */
            if (rb->head != ngx_http_lua_log_ringbuf_next_header(rb)) {
                break;
            }

            head = (ngx_http_lua_log_ringbuf_header_t *) rb->head;
            rb->head += HEADER_LEN + head->len;
            rb->count--;

            ngx_http_lua_log_ringbuf_next_header(rb);
            free_spaces = ngx_http_lua_log_ringbuf_free_spaces(rb);
        } while (free_spaces < n + HEADER_LEN);
    }

    ngx_http_lua_log_ringbuf_append(rb, 0, log_level, buf, n);

    return NGX_OK;
}


/* read log from ring buffer, do reset if all of the logs were readed. */
ngx_int_t
ngx_http_lua_log_ringbuf_read(ngx_http_lua_log_ringbuf_t *rb, int *log_level,
    void **buf, size_t *n)
{
    ngx_http_lua_log_ringbuf_header_t       *head;

    if (rb->count == 0) {
        return NGX_ERROR;
    }

    head = (ngx_http_lua_log_ringbuf_header_t *)
           ngx_http_lua_log_ringbuf_next_header(rb);

    if (rb->head >= rb->sentinel) {
        return NGX_ERROR;
    }

    *log_level = head->log_level;
    *n = head->len;
    rb->head += HEADER_LEN;
    *buf = rb->head;
    rb->head += head->len;
    rb->count--;

    if (rb->count == 0) {
        ngx_http_lua_log_ringbuf_reset(rb);
    }

    return NGX_OK;
}
