
/*
 * Copyright (C) Yichun Zhang (agentzh)
 * Copyright (C) cuiweixie
 * I hereby assign copyright in this code to the lua-nginx-module project,
 * to be licensed under the same terms as the rest of the code.
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
    int n, char **errmsg);
int ngx_http_lua_ffi_semaphore_post(ngx_http_lua_semaphore_t *sem,
    int n);
int ngx_http_lua_ffi_semaphore_wait(ngx_http_request_t *r,
    ngx_http_lua_semaphore_t *sem, int wait_ms, u_char *err, size_t *errlen);
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
    ngx_http_lua_semaphore_t            *sem, *iter;
    ngx_http_lua_main_conf_t            *lmcf;
    ngx_queue_t                         *q;
    ngx_uint_t                           i, n;
    ngx_http_lua_semaphore_mm_block_t   *block;
    ngx_http_lua_semaphore_mm_t         *mm;

    ngx_http_lua_assert(ngx_cycle && ngx_cycle->conf_ctx);

    lmcf = ngx_http_cycle_get_module_main_conf(ngx_cycle,
                                               ngx_http_lua_module);

    mm = lmcf->semaphore_mm;

    if (!ngx_queue_empty(&mm->free_queue)) {
        q = ngx_queue_head(&mm->free_queue);
        ngx_queue_remove(q);

        sem = ngx_queue_data(q, ngx_http_lua_semaphore_t, chain);

        sem->block->used++;

        ngx_memzero(&sem->sem_event, sizeof(ngx_event_t));

        sem->sem_event.handler = ngx_http_lua_semaphore_handler;
        sem->sem_event.data = sem;
        sem->sem_event.log = ngx_cycle->log;

        mm->used++;

        ngx_log_debug1(NGX_LOG_DEBUG_HTTP, ngx_cycle->log, 0,
                       "from head of free queue, alloc semaphore: %p", sem);

        return sem;
    }

    /* free_queue is empty */

    n = sizeof(ngx_http_lua_semaphore_mm_block_t)
        + mm->num_per_block * sizeof(ngx_http_lua_semaphore_t);

    dd("block size: %d, item size: %d",
       (int) sizeof(ngx_http_lua_semaphore_mm_block_t),
       (int) sizeof(ngx_http_lua_semaphore_t));

    block = ngx_alloc(n, ngx_cycle->log);
    if (block == NULL) {
        return NULL;
    }

    mm->cur_epoch++;
    mm->total += mm->num_per_block;
    mm->used++;

    block->mm = mm;
    block->epoch = mm->cur_epoch;

    sem = (ngx_http_lua_semaphore_t *) (block + 1);
    sem->block = block;
    sem->block->used = 1;

    ngx_memzero(&sem->sem_event, sizeof(ngx_event_t));

    sem->sem_event.handler = ngx_http_lua_semaphore_handler;
    sem->sem_event.data = sem;
    sem->sem_event.log = ngx_cycle->log;

    for (iter = sem + 1, i = 1; i < mm->num_per_block; i++, iter++) {
        iter->block = block;
        ngx_queue_insert_tail(&mm->free_queue, &iter->chain);
    }

    ngx_log_debug2(NGX_LOG_DEBUG_HTTP, ngx_cycle->log, 0,
                   "new block, alloc semaphore: %p block: %p", sem, block);

    return sem;
}


void
ngx_http_lua_cleanup_semaphore_mm(void *data)
{
    ngx_http_lua_semaphore_t            *sem, *iter;
    ngx_uint_t                           i;
    ngx_http_lua_main_conf_t            *lmcf;
    ngx_queue_t                         *q;
    ngx_http_lua_semaphore_mm_block_t   *block;
    ngx_http_lua_semaphore_mm_t         *mm;

    lmcf = (ngx_http_lua_main_conf_t *) data;
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
            /* just return directly when some thing goes wrong */

            ngx_log_error(NGX_LOG_ALERT, ngx_cycle->log, 0,
                          "ngx_http_lua_cleanup_semaphore_mm when cleanup"
                          " block %p is still used by someone", block);

            return;
        }
    }

    dd("ngx_http_lua_cleanup_semaphore_mm");
}


static void
ngx_http_lua_free_semaphore(ngx_http_lua_semaphore_t *sem)
{
    ngx_http_lua_semaphore_t            *iter;
    ngx_uint_t                           i, mid_epoch;
    ngx_http_lua_semaphore_mm_block_t   *block;
    ngx_http_lua_semaphore_mm_t         *mm;

    block = sem->block;
    block->used--;

    mm = block->mm;
    mm->used--;

    mid_epoch = mm->cur_epoch - ((mm->total / mm->num_per_block) >> 1);

    if (block->epoch < mid_epoch) {
        ngx_queue_insert_tail(&mm->free_queue, &sem->chain);
        ngx_log_debug4(NGX_LOG_DEBUG_HTTP, ngx_cycle->log, 0,
                       "add to free queue tail semaphore: %p epoch: %d"
                       "mid_epoch: %d cur_epoch: %d", sem, (int) block->epoch,
                       (int) mid_epoch, (int) mm->cur_epoch);

    } else {
        ngx_queue_insert_head(&mm->free_queue, &sem->chain);
        ngx_log_debug4(NGX_LOG_DEBUG_HTTP, ngx_cycle->log, 0,
                       "add to free queue head semaphore: %p epoch: %d"
                       "mid_epoch: %d cur_epoch: %d", sem, (int) block->epoch,
                       (int) mid_epoch, (int) mm->cur_epoch);
    }

    dd("used: %d", (int) block->used);

    if (block->used == 0
        && mm->used <= (mm->total >> 1)
        && block->epoch < mid_epoch)
    {
        /* load <= 50% and it's on the older side */
        iter = (ngx_http_lua_semaphore_t *) (block + 1);

        for (i = 0; i < mm->num_per_block; i++, iter++) {
            ngx_queue_remove(&iter->chain);
        }

        mm->total -= mm->num_per_block;

        ngx_log_debug1(NGX_LOG_DEBUG_HTTP, ngx_cycle->log, 0,
                       "free semaphore block: %p", block);

        ngx_free(block);
    }
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
    int n, char **errmsg)
{
    ngx_http_lua_semaphore_t    *sem;

    sem = ngx_http_lua_alloc_semaphore();
    if (sem == NULL) {
        *errmsg = "no memory";
        return NGX_ERROR;
    }

    ngx_queue_init(&sem->wait_queue);

    sem->resource_count = n;
    sem->wait_count = 0;
    *psem = sem;

    ngx_log_debug2(NGX_LOG_DEBUG_HTTP, ngx_cycle->log, 0,
                   "http lua semaphore new: %p, resources: %d",
                   sem, sem->resource_count);

    return NGX_OK;
}


int
ngx_http_lua_ffi_semaphore_post(ngx_http_lua_semaphore_t *sem, int n)
{
    ngx_log_debug3(NGX_LOG_DEBUG_HTTP, ngx_cycle->log, 0,
                   "http lua semaphore post: %p, n: %d, resources: %d",
                   sem, n, sem->resource_count);

    sem->resource_count += n;

    if (!ngx_queue_empty(&sem->wait_queue)) {
        /* we need the extra paranthese around the first argument of
         * ngx_post_event() just to work around macro issues in nginx
         * cores older than nginx 1.7.12 (exclusive).
         */
        ngx_post_event((&sem->sem_event), &ngx_posted_events);
    }

    return NGX_OK;
}


int
ngx_http_lua_ffi_semaphore_wait(ngx_http_request_t *r,
    ngx_http_lua_semaphore_t *sem, int wait_ms, u_char *err, size_t *errlen)
{
    ngx_http_lua_ctx_t           *ctx;
    ngx_http_lua_co_ctx_t        *wait_co_ctx;
    ngx_int_t                     rc;

    ngx_log_debug4(NGX_LOG_DEBUG_HTTP, ngx_cycle->log, 0,
                   "http lua semaphore wait: %p, timeout: %d, "
                   "resources: %d, event posted: %d",
                   sem, wait_ms, sem->resource_count,
#if (nginx_version >= 1007005)
                   (int) sem->sem_event.posted
#else
                   sem->sem_event.prev ? 1 : 0
#endif
                   );

    ctx = ngx_http_get_module_ctx(r, ngx_http_lua_module);
    if (ctx == NULL) {
        *errlen = ngx_snprintf(err, *errlen, "no request ctx found") - err;
        return NGX_ERROR;
    }

    rc = ngx_http_lua_ffi_check_context(ctx, NGX_HTTP_LUA_CONTEXT_REWRITE
                                        | NGX_HTTP_LUA_CONTEXT_ACCESS
                                        | NGX_HTTP_LUA_CONTEXT_CONTENT
                                        | NGX_HTTP_LUA_CONTEXT_TIMER
                                        | NGX_HTTP_LUA_CONTEXT_SSL_CERT,
                                        err, errlen);

    if (rc != NGX_OK) {
        return NGX_ERROR;
    }

    /* we keep the order, will resume the older waited firtly
     * in ngx_http_lua_semaphore_handler
     */

    if (ngx_queue_empty(&sem->wait_queue) && sem->resource_count > 0) {
        sem->resource_count--;
        return NGX_OK;
    }

    if (wait_ms == 0) {
        return NGX_DECLINED;
    }

    sem->wait_count++;
    wait_co_ctx = ctx->cur_co_ctx;

    wait_co_ctx->sleep.handler = ngx_http_lua_semaphore_timeout_handler;
    wait_co_ctx->sleep.data = ctx->cur_co_ctx;
    wait_co_ctx->sleep.log = r->connection->log;

    ngx_add_timer(&wait_co_ctx->sleep, (ngx_msec_t) wait_ms);

    dd("ngx_http_lua_ffi_semaphore_wait add timer coctx:%p wait: %d(ms)",
       wait_co_ctx, wait_ms);

    ngx_queue_insert_tail(&sem->wait_queue, &wait_co_ctx->sem_wait_queue);

    wait_co_ctx->data = sem;
    wait_co_ctx->cleanup = ngx_http_lua_semaphore_cleanup;

    ngx_log_debug0(NGX_LOG_DEBUG_HTTP, ngx_cycle->log, 0,
                   "http lua semaphore wait yielding");

    return NGX_AGAIN;
}


int
ngx_http_lua_ffi_semaphore_count(ngx_http_lua_semaphore_t *sem)
{
    return sem->resource_count - sem->wait_count;
}


static void
ngx_http_lua_semaphore_cleanup(void *data)
{
    ngx_http_lua_co_ctx_t          *coctx = data;
    ngx_queue_t                    *q;
    ngx_http_lua_semaphore_t       *sem;

    sem = coctx->data;

    ngx_log_debug0(NGX_LOG_DEBUG_HTTP, ngx_cycle->log, 0,
                   "http lua semaphore cleanup");

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
    ngx_http_lua_semaphore_t    *sem;
    ngx_http_request_t          *r;
    ngx_http_lua_ctx_t          *ctx;
    ngx_http_lua_co_ctx_t       *wait_co_ctx;
    ngx_connection_t            *c;
    ngx_queue_t                 *q;

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
        ngx_http_lua_assert(ctx != NULL);

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
    ngx_http_lua_assert(ctx != NULL);

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
                   "in lua gc, semaphore %p", sem);

    if (sem == NULL) {
        return;
    }

    if (!ngx_queue_empty(&sem->wait_queue)) {
        ngx_log_error(NGX_LOG_CRIT, ngx_cycle->log, 0,
                      "in lua semaphore gc wait queue is"
                      " not empty while the semaphore %p is being "
                      "destroyed", sem);
    }

    ngx_http_lua_free_semaphore(sem);
}


#endif /* NGX_LUA_NO_FFI_API */

/* vi:set ft=c ts=4 sw=4 et fdm=marker: */
