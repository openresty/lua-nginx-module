
#ifndef DDEBUG
#define DDEBUG 0
#endif
#include "ddebug.h"


#include "ngx_http_lua_common.h"
#include "ngx_http_lua_log_ringbuf.h"


typedef struct {
    unsigned    is_data:1;
    unsigned    log_level:4;
    int    len;
} ngx_http_lua_log_ringbuf_header_t;


static void * ngx_http_lua_log_ringbuf_head(ngx_http_lua_log_ringbuf_t *rb);
static void ngx_http_lua_log_ringbuf_append_tail(
    ngx_http_lua_log_ringbuf_t *rb, int is_data, int log_level, void *buf,
    int n);
static size_t ngx_http_lua_log_ringbuf_rleft(ngx_http_lua_log_ringbuf_t *rb);


void
ngx_http_lua_log_ringbuf_init(ngx_http_lua_log_ringbuf_t *rb, void *buf,
    size_t len)
{
    rb->data = buf;
    rb->size = len;

    rb->tail = rb->data;
    rb->head = rb->data;
    rb->count = 0;
    rb->filter_level = NGX_LOG_DEBUG;

    return;
}


void
ngx_http_lua_log_ringbuf_reset(ngx_http_lua_log_ringbuf_t *rb)
{
    rb->tail = rb->data;
    rb->head = rb->data;
    rb->count = 0;

    return;
}


static void *
ngx_http_lua_log_ringbuf_head(ngx_http_lua_log_ringbuf_t *rb)
{
    ngx_http_lua_log_ringbuf_header_t       *head;

    /* useless data */
    if (rb->size - (rb->head - rb->data) <
        sizeof(ngx_http_lua_log_ringbuf_header_t))
    {
        rb->head = rb->data;
        return rb->head;
    }

    /* placehold data */
    head = (ngx_http_lua_log_ringbuf_header_t *) rb->head;
    if (!head->is_data) {
        rb->head = rb->data;
        return rb->head;
    }

    return rb->head;
}


static void
ngx_http_lua_log_ringbuf_append_tail(ngx_http_lua_log_ringbuf_t *rb,
    int is_data, int log_level, void *buf, int n)
{
    ngx_http_lua_log_ringbuf_header_t        *head;

    head = (ngx_http_lua_log_ringbuf_header_t *) rb->tail;
    head->len = n;
    head->log_level = log_level;
    head->is_data = is_data;

    if (!is_data) {
        rb->tail = rb->data;
        return;
    }

    rb->tail += sizeof(ngx_http_lua_log_ringbuf_header_t);
    ngx_memcpy(rb->tail, buf, n);
    rb->tail += n;
    rb->count++;

    return;
}


static size_t
ngx_http_lua_log_ringbuf_rleft(ngx_http_lua_log_ringbuf_t *rb)
{
    if (rb->tail >= rb->head) {
        return rb->data + rb->size - rb->tail;
    }

    return rb->head - rb->tail;
}


ngx_int_t
ngx_http_lua_log_ringbuf_write(ngx_http_lua_log_ringbuf_t *rb, int log_level,
    void *buf, size_t n)
{
    size_t              rleft, head_len;

    ngx_http_lua_log_ringbuf_header_t       *head;

    head_len = sizeof(ngx_http_lua_log_ringbuf_header_t);

    if (n + head_len > rb->size) {
        return NGX_ERROR;
    }

    rleft = ngx_http_lua_log_ringbuf_rleft(rb);

    if (rleft < n + head_len) {
        /*  set placehold */
        ngx_http_lua_log_ringbuf_append_tail(rb, 0, 0, 0, 0);

        rb->tail = rb->data;

        do {                                   /*  throw away old data */
            if (rb->head != ngx_http_lua_log_ringbuf_head(rb)) {
                break;
            }

            head = (ngx_http_lua_log_ringbuf_header_t *) rb->head;
            rb->head += head_len + head->len;
            rb->count--;

            ngx_http_lua_log_ringbuf_head(rb);
            rleft = ngx_http_lua_log_ringbuf_rleft(rb);
        } while (rleft < n + head_len);
    }

    ngx_http_lua_log_ringbuf_append_tail(rb, 1, log_level, buf, n);

    return NGX_OK;
}


ngx_int_t
ngx_http_lua_log_ringbuf_read(ngx_http_lua_log_ringbuf_t *rb, int *log_level,
    void **buf, size_t *n)
{
    ngx_http_lua_log_ringbuf_header_t       *head;

    if (rb->count == 0) {
        return NGX_ERROR;
    }

    head = (ngx_http_lua_log_ringbuf_header_t *)
           ngx_http_lua_log_ringbuf_head(rb);

    if (!head->is_data) {
        return NGX_ERROR;
    }

    *log_level = head->log_level;
    *n = head->len;
    rb->head += sizeof(ngx_http_lua_log_ringbuf_header_t);
    *buf = rb->head;
    rb->head += head->len;
    rb->count--;

    if (rb->count == 0) {
        ngx_http_lua_log_ringbuf_reset(rb);
    }

    return NGX_OK;
}
