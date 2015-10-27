
/*
 * Copyright (C) cuiweixie
 */

#ifndef NGX_LUA_NO_FFI_API


#ifndef DDEBUG
#define DDEBUG 0
#endif
#include "ddebug.h"


#include "ngx_http_lua_util.h"
#include "ngx_http_lua_semaphore.h"
#include "ngx_http_lua_contentby.h"


ngx_int_t ngx_http_lua_semaphore_init_mm(ngx_http_lua_semaphore_mm_t *mm);
static ngx_http_lua_semaphore_t *ngx_http_lua_alloc_semaphore(void);
void ngx_http_lua_cleanup_semaphore_mm(void *data);
static void ngx_http_lua_free_semaphore(ngx_http_lua_semaphore_t *sem);
static ngx_int_t ngx_http_lua_semaphore_resume(ngx_http_request_t *r);
int ngx_http_lua_ffi_semaphore_new(ngx_http_lua_semaphore_t **psem,
    int n, char **errstr);
int ngx_http_lua_ffi_semaphore_post(ngx_http_lua_semaphore_t *sem,
    int n, char **errstr);
int ngx_http_lua_ffi_semaphore_wait(ngx_http_request_t *r,
    ngx_http_lua_semaphore_t *sem, int time, u_char *errstr, size_t *errlen);
static void ngx_http_lua_semaphore_cleanup(void *data);
static void ngx_http_lua_semaphore_handler(ngx_event_t *ev);
static void ngx_http_lua_semaphore_timeout_handler(ngx_event_t *ev);
void ngx_http_lua_ffi_semaphore_gc(ngx_http_lua_semaphore_t *sem);


enum {
    SEMAPHORE_WAIT_SUCC = 0,
    SEMAPHORE_WAIT_TIMEOUT = 1
};


static ngx_http_lua_semaphore_t *
ngx_http_lua_alloc_semaphore(void)
{
    ngx_http_lua_semaphore_t          *sem;
    ngx_http_lua_semaphore_t          *iter;
    ngx_http_lua_main_conf_t          *lmcf;
    ngx_queue_t                       *q;
    ngx_uint_t                         i, n;
    ngx_http_lua_semaphore_mm_block_t *block;
    ngx_http_lua_semaphore_mm_t       *mm;

    if (!ngx_cycle || !ngx_cycle->conf_ctx) {
        dd("in ngx_http_lua_alloc_semaphore"
           "ngx_cycle or ngx_cycle->conf_ctx is null");

        return NULL;
    }

    lmcf = ngx_http_cycle_get_module_main_conf(ngx_cycle,
                                               ngx_http_lua_module);

    if (!lmcf) {
        dd("in ngx_http_lua_alloc_semaphore lmcf is null");
        return NULL;
    }

    mm = lmcf->semaphore_mm;

    if (!ngx_queue_empty(&mm->free_queue)) {
        q = ngx_queue_head(&mm->free_queue);
        ngx_queue_remove(q);

        sem = ngx_queue_data(q, ngx_http_lua_semaphore_t, chain);
        sem->block->used++;

        mm->used++;

        return sem;
    }

    /* free_queue is empty */

    n = sizeof(ngx_http_lua_semaphore_mm_block_t)
        + mm->num_per_block * sizeof(ngx_http_lua_semaphore_t);

    block = ngx_alloc(n, ngx_cycle->log);

    if (block == NULL) {
        return NULL;
    }

    dd("alloc semaphore block:%p", block);

    mm->cur_epoch++;
    mm->total += mm->num_per_block;
    mm->used++;

    block->mm = mm;
    block->epoch = mm->cur_epoch;

    sem = (ngx_http_lua_semaphore_t *) (block + 1);
    sem->block = block;
    sem->block->used = 1;

    for (iter = sem + 1, i = 1; i < mm->num_per_block; i++, iter++) {
        iter->block = block;
        ngx_queue_insert_tail(&mm->free_queue, &iter->chain);
    }

    dd("ngx_http_lua_alloc_semaphore sem: %p", sem);

    return sem;
}


void
ngx_http_lua_cleanup_semaphore_mm(void *data)
{
    ngx_http_lua_semaphore_t            *sem;
    ngx_http_lua_semaphore_t            *iter;
    ngx_uint_t                           i;
    ngx_http_lua_main_conf_t            *lmcf;
    ngx_queue_t                         *q;
    ngx_http_lua_semaphore_mm_block_t   *block;
    ngx_http_lua_semaphore_mm_t         *mm;

    lmcf = (ngx_http_lua_main_conf_t*) data;
    mm = lmcf->semaphore_mm;

    while (!ngx_queue_empty(&mm->free_queue)) {

        q = ngx_queue_head(&mm->free_queue);
        sem = ngx_queue_data(q, ngx_http_lua_semaphore_t, chain);
        block = sem->block;

        if (block->used == 0) {
            iter = (ngx_http_lua_semaphore_t *) (block + 1);

            for (i = 0; i < block->mm->num_per_block; i++, iter++) {
                ngx_queue_remove(&iter->chain);
            }

            dd("free semaphore block: %p at final", block);

            ngx_free(block);

        } else {
            ngx_log_error(NGX_LOG_CRIT, ngx_cycle->log, 0,
               "ngx_http_lua_cleanup_semaphore_mm when cleanup"
               " block: %p is still using by someone", block);
        }
    }

    dd("ngx_http_lua_cleanup_semaphore_mm");
}


static void
ngx_http_lua_free_semaphore(ngx_http_lua_semaphore_t *sem)
{
    ngx_http_lua_semaphore_t          *iter;
    ngx_int_t                          start_epoch;
    ngx_uint_t                         i;
    ngx_http_lua_semaphore_mm_block_t *block;
    ngx_http_lua_semaphore_mm_t       *mm;

    block = sem->block;
    block->used--;

    mm = block->mm;
    mm->used--;

    start_epoch = mm->cur_epoch - mm->total/mm->num_per_block;

    if (sem->block->used < (mm->num_per_block >> 1)
        && block->epoch <= start_epoch + ((mm->cur_epoch - start_epoch) >> 1))
    {
        ngx_queue_insert_tail(&mm->free_queue, &sem->chain);

    } else {
        ngx_queue_insert_head(&mm->free_queue, &sem->chain);
    }

    if (block->used == 0 && mm->used < (mm->total >> 1)
        && block->epoch <= (start_epoch + ((mm->cur_epoch-start_epoch) >> 1)))
    {
        /* load <= 50% and it's the older */
        iter = (ngx_http_lua_semaphore_t*) (block+1);
        for (i = 0; i < mm->num_per_block; i++, iter++) {
            ngx_queue_remove(&iter->chain);
        }

        dd("free semaphore block: %p at procedure",block);

        mm->total -= mm->num_per_block;
        ngx_free(block);
    }

    dd("ngx_http_lua_free_semaphore sem: %p "
       "sem->chain.prev: %p sem->chain.next: %p",
       sem, sem->chain.prev, sem->chain.next);
}


static ngx_int_t
ngx_http_lua_semaphore_resume(ngx_http_request_t *r)
{
    lua_State                   *vm;
    ngx_connection_t            *c;
    ngx_int_t                    rc;
    ngx_http_lua_ctx_t          *ctx;

    ctx = ngx_http_get_module_ctx(r, ngx_http_lua_module);
    if (ctx == NULL) {
        return NGX_ERROR;
    }

    ctx->resume_handler = ngx_http_lua_wev_handler;

    c = r->connection;
    vm = ngx_http_lua_get_lua_vm(r, ctx);

    if (ctx->cur_co_ctx->sem_resume_status == SEMAPHORE_WAIT_SUCC) {
         lua_pushboolean(ctx->cur_co_ctx->co, 1);
         lua_pushnil(ctx->cur_co_ctx->co);

    } else {
         lua_pushboolean(ctx->cur_co_ctx->co, 0);
         lua_pushstring(ctx->cur_co_ctx->co, "timeout");
    }

    rc = ngx_http_lua_run_thread(vm, r, ctx, 2);

    ngx_log_debug1(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                   "lua run thread returned %d", rc);

    if (rc == NGX_AGAIN) {
        return ngx_http_lua_run_posted_threads(c, vm, r, ctx);
    }

    if (rc == NGX_DONE) {
        ngx_http_lua_finalize_request(r, NGX_DONE);
        return ngx_http_lua_run_posted_threads(c, vm, r, ctx);
    }

    /* rc == NGX_ERROR || rc >= NGX_OK */
    if (ctx->entered_content_phase) {
        ngx_http_lua_finalize_request(r, rc);
        return NGX_DONE;
    }

    return rc;
}


int
ngx_http_lua_ffi_semaphore_new(ngx_http_lua_semaphore_t **psem,
    int n, char **errstr)
{
    ngx_http_lua_semaphore_t *sem;

    sem = ngx_http_lua_alloc_semaphore();
    if (sem == NULL) {
        *errstr = "ngx_http_lua_ffi_semaphore_new ngx_alloc failed";
        return NGX_ERROR;
    }

    ngx_queue_init(&sem->wait_queue);

    sem->resource_count = n;
    sem->wait_count = 0;
    sem->in_post_event = 0;
    sem->log = ngx_cycle->log;
    *psem = sem;

    dd("ngx_http_lua_ffi_semaphore_new semaphore: %p, resource_count: %d",
       sem, sem->resource_count);

    return NGX_OK;
}


int
ngx_http_lua_ffi_semaphore_post(ngx_http_lua_semaphore_t *sem,
    int n, char **errstr)
{
    if (sem == NULL) {
        *errstr = "semaphore is null";
        return NGX_ERROR;
    }

    sem->resource_count += n;

    dd("ngx_http_lua_ffi_semaphore_post semaphore: %p, resource_count: %d",
       sem, sem->resource_count);

    if (!sem->in_post_event && !ngx_queue_empty(&sem->wait_queue)) {

        sem->sem_event.handler = ngx_http_lua_semaphore_handler;
        sem->sem_event.data = sem;
        sem->sem_event.log = sem->log;

        sem->in_post_event = 1;
        ngx_post_event((&sem->sem_event), &ngx_posted_events);
    }

    return NGX_OK;
}


int
ngx_http_lua_ffi_semaphore_wait(ngx_http_request_t *r,
    ngx_http_lua_semaphore_t *sem, int time,u_char *errstr, size_t *errlen)
{
    ngx_http_lua_ctx_t           *ctx;
    ngx_http_lua_co_ctx_t        *wait_co_ctx;
    ngx_int_t                     rc;

    if (r == NULL) {
        *errlen = ngx_snprintf(errstr, *errlen, "request is null") - errstr;
         return NGX_ERROR;
    }

    dd("ngx_http_lua_ffi_semaphore_wait semaphore: %p"
       "value: %d, in_post_event: %d",
       sem, sem->resource_count, sem->in_post_event);

    ctx = ngx_http_get_module_ctx(r, ngx_http_lua_module);
    if (ctx == NULL) {
        *errlen = ngx_snprintf(errstr, *errlen, "ctx is null") - errstr;
        return NGX_ERROR;
    }

    rc = ngx_http_lua_ffi_check_context(ctx, (NGX_HTTP_LUA_CONTEXT_REWRITE
                                        | NGX_HTTP_LUA_CONTEXT_ACCESS
                                        | NGX_HTTP_LUA_CONTEXT_CONTENT
                                        | NGX_HTTP_LUA_CONTEXT_TIMER),
                                        errstr, errlen);

    if (rc == NGX_DECLINED) {
        return NGX_ERROR;
    }

    if (!sem->in_post_event && sem->resource_count > 0) {
         sem->resource_count--;
         return NGX_OK;
    }

    if (time == 0) {
        return NGX_DECLINED;
    }

    sem->wait_count++;
    wait_co_ctx = ctx->cur_co_ctx;

    wait_co_ctx->sleep.handler = ngx_http_lua_semaphore_timeout_handler;
    wait_co_ctx->sleep.data = ctx->cur_co_ctx;
    wait_co_ctx->sleep.log = r->connection->log;

    ngx_add_timer(&wait_co_ctx->sleep, (ngx_msec_t) time * 1000);

    dd("ngx_http_lua_ffi_semaphore_wait add timer coctx:%p time:%d(s)",
        wait_co_ctx, time);

    ngx_queue_insert_tail(&sem->wait_queue, &wait_co_ctx->sem_wait_queue);
    wait_co_ctx->data = sem;
    wait_co_ctx->cleanup = ngx_http_lua_semaphore_cleanup;

    return NGX_AGAIN;
}


static void
ngx_http_lua_semaphore_cleanup(void *data)
{
    ngx_http_lua_co_ctx_t          *coctx = data;
    ngx_queue_t                    *q;
    ngx_http_lua_semaphore_t       *sem;

    sem = coctx->data;

    ngx_log_debug0(NGX_LOG_DEBUG_HTTP, sem->log, 0,
                   "ngx_http_lua_semaphore_cleanup");

    if (coctx->sleep.timer_set) {
        ngx_del_timer(&coctx->sleep);
    }

    q = &coctx->sem_wait_queue;

    ngx_queue_remove(q);
    sem->wait_count--;
    coctx->cleanup = NULL;
}


static void
ngx_http_lua_semaphore_handler(ngx_event_t *ev)
{
    ngx_http_lua_semaphore_t          *sem;
    ngx_http_request_t                *r;
    ngx_http_lua_ctx_t                *ctx;
    ngx_http_lua_co_ctx_t             *wait_co_ctx;
    ngx_connection_t                  *c;
    ngx_queue_t                       *q;

    sem = ev->data;

    while (!ngx_queue_empty(&sem->wait_queue) && sem->resource_count > 0) {

        q = ngx_queue_head(&sem->wait_queue);
        ngx_queue_remove(q);

        sem->wait_count--;

        wait_co_ctx = ngx_queue_data(q, ngx_http_lua_co_ctx_t, sem_wait_queue);
        wait_co_ctx->cleanup = NULL;

        if (wait_co_ctx->sleep.timer_set) {
            ngx_del_timer(&wait_co_ctx->sleep);
        }

        r = ngx_http_lua_get_req(wait_co_ctx->co);
        c = r->connection;

        ctx = ngx_http_get_module_ctx(r, ngx_http_lua_module);
        if (ctx == NULL) {
            continue;
        }

        sem->resource_count--;

        ctx->cur_co_ctx = wait_co_ctx;

        wait_co_ctx->sem_resume_status = SEMAPHORE_WAIT_SUCC;

        if (ctx->entered_content_phase) {
            (void) ngx_http_lua_semaphore_resume(r);

        } else {
            ctx->resume_handler = ngx_http_lua_semaphore_resume;
            ngx_http_core_run_phases(r);
        }

        ngx_http_run_posted_requests(c);
    }

    /* after dealing with semaphore post event */
    sem->in_post_event = 0;
}


static void
ngx_http_lua_semaphore_timeout_handler(ngx_event_t *ev)
{
    ngx_http_lua_co_ctx_t       *wait_co_ctx;
    ngx_http_request_t          *r;
    ngx_http_lua_ctx_t          *ctx;
    ngx_connection_t            *c;
    ngx_http_lua_semaphore_t    *sem;

    wait_co_ctx = ev->data;
    wait_co_ctx->cleanup = NULL;

    dd("ngx_http_lua_semaphore_timeout_handler timeout coctx:%p", wait_co_ctx);

    sem = wait_co_ctx->data;

    ngx_queue_remove(&wait_co_ctx->sem_wait_queue);
    sem->wait_count--;

    r = ngx_http_lua_get_req(wait_co_ctx->co);
    c = r->connection;

    ctx = ngx_http_get_module_ctx(r, ngx_http_lua_module);
    if (ctx == NULL) {
        return;
    }

    ctx->cur_co_ctx = wait_co_ctx;

    wait_co_ctx->sem_resume_status = SEMAPHORE_WAIT_TIMEOUT;

    if (ctx->entered_content_phase) {
        (void) ngx_http_lua_semaphore_resume(r);

    } else {
         ctx->resume_handler = ngx_http_lua_semaphore_resume;
         ngx_http_core_run_phases(r);
    }

    ngx_http_run_posted_requests(c);
}


void
ngx_http_lua_ffi_semaphore_gc(ngx_http_lua_semaphore_t *sem)
{
    ngx_log_debug1(NGX_LOG_DEBUG_HTTP, ngx_cycle->log, 0,
                   "ngx_http_lua_ffi_semaphore_gc %p", sem);

    if (sem == NULL) {
        return;
    }

    if (!ngx_queue_empty(&sem->wait_queue)) {
        ngx_log_error(NGX_LOG_CRIT, ngx_cycle->log, 0,
                       "ngx_http_lua_ffi_semaphore_gc wait queue is"
                       " not empty while the semaphore: %p is "
                       "going to be destroyed", sem);
    }

    ngx_http_lua_free_semaphore(sem);
}


#endif /* NGX_LUA_NO_FFI_API */

/* vi:set ft=c ts=4 sw=4 et fdm=marker: */
