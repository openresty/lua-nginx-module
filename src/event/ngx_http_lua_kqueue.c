
/*
 * Copyright (C) Yichun Zhang (agentzh)
 */


#include <ngx_core.h>
#include <ngx_event.h>
#include <ngx_http.h>
#include "../ngx_http_lua_event.h"


static ngx_int_t ngx_http_lua_kqueue_init_event(ngx_cycle_t *cycle);
static ngx_int_t ngx_http_lua_kqueue_set_event(ngx_event_t *ev,
    ngx_int_t event);
static ngx_int_t ngx_http_lua_kqueue_clear_event(ngx_event_t *ev,
    ngx_int_t event);
static ngx_int_t ngx_http_lua_kqueue_process_event(ngx_http_request_t *r,
    ngx_msec_t timer);

int                    kq = -1;
static struct kevent   kch;
static struct kevent   kev;

ngx_http_lua_event_actions_t  ngx_http_lua_kqueue = {
    ngx_http_lua_kqueue_init_event,
    ngx_http_lua_kqueue_set_event,
    ngx_http_lua_kqueue_clear_event,
    ngx_http_lua_kqueue_process_event,
};


static ngx_int_t
ngx_http_lua_kqueue_init_event(ngx_cycle_t *cycle)
{
    kq = kqueue();

    if (kq == -1) {
        ngx_log_error(NGX_LOG_EMERG, cycle->log, ngx_errno,
                      "lua kqueue() failed");

        return NGX_ERROR;
    }

    return NGX_OK;
}


static ngx_int_t
ngx_http_lua_kqueue_set_event(ngx_event_t *ev, ngx_int_t event)
{
    ngx_connection_t  *c;

    c = ev->data;

    ev->active = 1;

    kch.ident = c->fd;
    kch.filter = (short) event;
    kch.flags = EV_ADD|EV_ENABLE;
    kch.udata = NGX_KQUEUE_UDATA_T (ev);

    return NGX_OK;
}


static ngx_int_t
ngx_http_lua_kqueue_clear_event(ngx_event_t *ev, ngx_int_t event)
{
    ngx_connection_t  *c;

    c = ev->data;

    ev->active = 0;

    kch.ident = c->fd;
    kch.filter = (short) event;
    kch.flags = EV_DELETE;
    kch.udata = NGX_KQUEUE_UDATA_T (ev);

    if (kevent(kq, &kch, 1, NULL, 0, NULL) == -1) {
        ngx_log_error(NGX_LOG_ALERT, r->connection->log, err,
                      "lua kevent() failed");

        return NGX_ERROR;
    }

    return NGX_OK;
}


static ngx_int_t
ngx_http_lua_kqueue_process_event(ngx_http_request_t *r, ngx_msec_t timer)
{
    int               events;
    struct timespec   ts;
    ngx_event_t      *ev;
    ngx_err_t         err;

    ts.tv_sec = timer / 1000;
    ts.tv_nsec = (timer % 1000) * 1000000;

    events = kevent(kq, &kch, 1, &kev, 1, &ts);

    err = (events == -1) ? ngx_errno : 0;

    if (err) {
        ngx_log_error(NGX_LOG_ALERT, r->connection->log, err,
                      "lua kevent() failed");

        return NGX_ERROR;
    }

    if (events == 0) {
        ngx_log_error(NGX_LOG_ALERT, r->connection->log, 0,
                      "lua kevent() returned no events without timeout");

        return NGX_ERROR;
    }

    ev = (ngx_event_t *) kev.udata;

    ev->available = kev.data;
    ev->ready = 1;

    if (kev.flags & EV_EOF) {
        ev->pending_eof = 1;
    }

    return NGX_OK;
}
