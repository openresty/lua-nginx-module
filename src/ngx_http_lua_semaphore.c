
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


int ngx_http_lua_ffi_set_semaphore_threshold(ngx_int_t threshold);
static ngx_http_lua_semaphore_t *ngx_http_lua_alloc_semaphore(ngx_log_t *log);
void ngx_http_lua_cleanup_semaphore(void *data);
static void ngx_http_lua_free_semaphore(ngx_http_lua_semaphore_t *sem, ngx_log_t *log);
static ngx_int_t ngx_http_lua_semaphore_resume(ngx_http_request_t *r);
int ngx_http_lua_ffi_semaphore_new(ngx_http_lua_semaphore_t **psem, int n, char **errstr);
int ngx_http_lua_ffi_semaphore_post(ngx_http_lua_semaphore_t *sem, int n, char **errstr);
int ngx_http_lua_ffi_semaphore_wait(ngx_http_request_t *r, ngx_http_lua_semaphore_t *sem,
    int time, u_char *errstr, size_t *errlen);
static void ngx_http_lua_ffi_semaphore_cleanup(void *data);
static void ngx_http_lua_ffi_semaphore_handler(ngx_event_t *ev);
static void ngx_http_lua_semaphore_timeout_handler(ngx_event_t *ev);
void ngx_http_lua_ffi_semaphore_gc(ngx_http_lua_semaphore_t *sem);


enum {
    SEMAPHORE_WAIT_SUCC = 0,
    SEMAPHORE_WAIT_TIMEOUT = 1
};


static ngx_http_lua_semaphore_t *ngx_http_lua_semaphore_free_list = NULL;
static ngx_int_t ngx_http_lua_semaphore_threshold = 0;
static ngx_int_t ngx_http_lua_semaphore_free_count = 0;


int
ngx_http_lua_ffi_set_semaphore_threshold(ngx_int_t threshold)
{
    ngx_http_lua_semaphore_threshold = threshold;
    return (int) ngx_http_lua_semaphore_threshold;
}


int
ngx_http_lua_ffi_get_semaphore_threshold()
{
    return (int) ngx_http_lua_semaphore_threshold;
}


static ngx_http_lua_semaphore_t *
ngx_http_lua_alloc_semaphore(ngx_log_t *log)
{
    ngx_http_lua_semaphore_t *sem;

    if (ngx_http_lua_semaphore_free_list) {
         sem = ngx_http_lua_semaphore_free_list;
         ngx_http_lua_semaphore_free_list = ngx_http_lua_semaphore_free_list->next;
         ngx_http_lua_semaphore_free_count--;

    } else {

        sem = ngx_alloc(sizeof(ngx_http_lua_semaphore_t), log);
        if (sem == NULL) {
            return NULL;
        }
    }

    dd("ngx_http_lua_alloc_semaphore sem:%p", sem);

    return sem;
}


void
ngx_http_lua_cleanup_semaphore(void *data)
{
    dd("ngx_http_lua_cleanup_semaphore");

    ngx_http_lua_semaphore_t *sem = ngx_http_lua_semaphore_free_list;

    while (sem != NULL)
    {
         ngx_http_lua_semaphore_free_list = ngx_http_lua_semaphore_free_list->next;
         ngx_free(sem);
         sem = ngx_http_lua_semaphore_free_list;
    }
}


static void
ngx_http_lua_free_semaphore(ngx_http_lua_semaphore_t *sem, ngx_log_t *log)
{
    ngx_int_t n;

    dd("ngx_http_lua_free_semaphore sem:%p", sem);

    sem->next = ngx_http_lua_semaphore_free_list;
    ngx_http_lua_semaphore_free_list = sem;
    ngx_http_lua_semaphore_free_count++;

    if (ngx_http_lua_semaphore_free_count >= ngx_http_lua_semaphore_threshold) {

         n = ngx_http_lua_semaphore_free_count >> 1;
         ngx_http_lua_semaphore_free_count -= n;

         while (n--) {
             sem = ngx_http_lua_semaphore_free_list;
             ngx_http_lua_semaphore_free_list = ngx_http_lua_semaphore_free_list->next;
             ngx_free(sem);
         }

         dd("ngx_http_lua_free_semaphore sem_count:%lld",
            (long long int) ngx_http_lua_semaphore_free_count);
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
ngx_http_lua_ffi_semaphore_new(ngx_http_lua_semaphore_t **psem, int n, char **errstr)
{
    ngx_http_lua_semaphore_t *sem;

    sem = ngx_http_lua_alloc_semaphore(ngx_cycle->log);
    if (sem == NULL) {
        *errstr = "ngx_http_lua_ffi_semaphore_new ngx_alloc failed";
        return NGX_ERROR;
    }

    ngx_memzero(sem, sizeof(ngx_http_lua_semaphore_t));
    ngx_queue_init(&sem->wait_queue);

    sem->count = n;
    sem->wait_count = 0;
    sem->in_post_event = 0;
    sem->log = ngx_cycle->log;
    *psem = sem;

    dd("ngx_http_lua_ffi_semaphore_new semaphore %p value %d", sem, sem->count);

    return NGX_OK;
}


int
ngx_http_lua_ffi_semaphore_post(ngx_http_lua_semaphore_t *sem, int n, char **errstr)
{
    if (sem == NULL) {
        *errstr = "semaphore is null";
        return NGX_ERROR;
    }

    sem->count += n;

    dd("ngx_http_lua_ffi_semaphore_post semaphore %p value %d", sem, sem->count);

    if (!sem->in_post_event && !ngx_queue_empty(&sem->wait_queue)) {

        sem->sem_event.handler = ngx_http_lua_ffi_semaphore_handler;
        sem->sem_event.data = sem;
        sem->sem_event.log = sem->log;

        sem->in_post_event = 1;
        ngx_post_event((&sem->sem_event), &ngx_posted_events);
    }

    return NGX_OK;
}


int
ngx_http_lua_ffi_semaphore_wait(ngx_http_request_t *r, ngx_http_lua_semaphore_t *sem,
                          int time,u_char *errstr, size_t *errlen)
{
    ngx_http_lua_ctx_t           *ctx;
    ngx_http_lua_co_ctx_t        *wait_co_ctx;
    ngx_int_t                     rc;

    if (r == NULL) {

        *errlen = ngx_snprintf(errstr, *errlen,"request is null") 
                  - errstr;
         return NGX_ERROR;
    }

    dd("ngx_http_lua_ffi_semaphore_wait semaphore: %p"
       "value: %d in_post_event: %d", sem, sem->count, sem->in_post_event);

    ctx = ngx_http_get_module_ctx(r, ngx_http_lua_module);
    if (ctx == NULL) {
        *errlen = ngx_snprintf(errstr, *errlen, "ctx is null")
                  - errstr;
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

    if (!sem->in_post_event && sem->count > 0) {
         sem->count--;
         return NGX_OK;

    } 

    if (time == 0) {

        return NGX_DECLINED;

    } else {
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
         wait_co_ctx->cleanup = ngx_http_lua_ffi_semaphore_cleanup;

         return NGX_AGAIN;
    }
}


static void
ngx_http_lua_ffi_semaphore_cleanup(void *data)
{
    ngx_http_lua_co_ctx_t          *coctx = data;
    ngx_queue_t                    *q;
    ngx_http_lua_semaphore_t       *sem;

    if (!coctx->sleep.timer_set) {
        return;
    }

    sem = coctx->data;

    ngx_log_debug0(NGX_LOG_DEBUG_HTTP, sem->log, 0,
                   "ngx_http_lua_semaphore_cleanup");

    ngx_del_timer(&coctx->sleep);

    q = &coctx->sem_wait_queue;

    ngx_queue_remove(q);
    sem->wait_count--;
    coctx->cleanup = NULL;
}


static void
ngx_http_lua_ffi_semaphore_handler(ngx_event_t *ev)
{
    ngx_http_lua_semaphore_t          *sem;
    ngx_http_request_t                *r;
    ngx_http_lua_ctx_t                *ctx;
    ngx_http_lua_co_ctx_t             *wait_co_ctx;
    ngx_connection_t                  *c;
    ngx_queue_t                       *q;

    sem = ev->data;

    while (!ngx_queue_empty(&sem->wait_queue) && sem->count > 0) {

         q = ngx_queue_head(&sem->wait_queue);
         ngx_queue_remove(q);
         wait_co_ctx = ngx_queue_data(q, ngx_http_lua_co_ctx_t, sem_wait_queue);

         sem->count--;
         sem->wait_count--;
         ngx_del_timer(&wait_co_ctx->sleep);
         wait_co_ctx->cleanup = NULL;

         r = ngx_http_lua_get_req(wait_co_ctx->co);

         ctx = ngx_http_get_module_ctx(r, ngx_http_lua_module);
         if (ctx == NULL) {
             continue;
         }

         wait_co_ctx->cleanup = NULL;
         ctx->cur_co_ctx = wait_co_ctx;
         wait_co_ctx->sem_resume_status = SEMAPHORE_WAIT_SUCC;
         c = r->connection;

         if (ctx->entered_content_phase) {
             (void) ngx_http_lua_semaphore_resume(r);

         } else {
             ctx->resume_handler = ngx_http_lua_semaphore_resume;
             ngx_http_core_run_phases(r);
         }

         ngx_http_run_posted_requests(c);
    }

    /* after dealing with emaphore post event */
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

    r = ngx_http_lua_get_req(wait_co_ctx->co);

    dd("ngx_http_lua_semaphore_timeout_handler timeout coctx:%p", wait_co_ctx);

    sem = wait_co_ctx->data;
    sem->wait_count--;
    wait_co_ctx->cleanup = NULL;
    ngx_queue_remove(&wait_co_ctx->sem_wait_queue);

    ctx = ngx_http_get_module_ctx(r, ngx_http_lua_module);
    if (ctx == NULL) {
        return;
    }

    ctx->cur_co_ctx = wait_co_ctx;

    wait_co_ctx->sem_resume_status = SEMAPHORE_WAIT_TIMEOUT;

    c = r->connection;

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

    if (sem == NULL){
        return;
    }

    if (!ngx_queue_empty(&sem->wait_queue)) {
        ngx_log_error(NGX_LOG_CRIT, ngx_cycle->log, 0,
                       "ngx_http_lua_ffi_semaphore_gc wait queue is"
                       " not empty while the semaphore is "
                       "going to be destroyed", sem);
    }

    ngx_http_lua_free_semaphore(sem, sem->log);
}


#endif /* NGX_LUA_NO_FFI_API */
/* vi:set ft=c ts=4 sw=4 et fdm=marker: */
