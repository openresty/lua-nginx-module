
/*
 * Copyright (C) Yichun Zhang (agentzh)
 */


#include <ngx_core.h>
#include <ngx_event.h>
#include <ngx_http.h>
#include "../ngx_http_lua_event.h"


static ngx_int_t ngx_http_lua_epoll_init_event(ngx_cycle_t *cycle);
static ngx_int_t ngx_http_lua_epoll_set_event(ngx_event_t *ev, ngx_int_t event);
static ngx_int_t ngx_http_lua_epoll_clear_event(ngx_event_t *ev,
    ngx_int_t event);
static ngx_int_t ngx_http_lua_epoll_process_event(ngx_http_request_t *r,
    ngx_msec_t timer);

static int                  ep = -1;

ngx_http_lua_event_actions_t  ngx_http_lua_epoll = {
    ngx_http_lua_epoll_init_event,
    ngx_http_lua_epoll_set_event,
    ngx_http_lua_epoll_clear_event,
    ngx_http_lua_epoll_process_event,
};


static ngx_int_t
ngx_http_lua_epoll_init_event(ngx_cycle_t *cycle)
{
    ep = epoll_create(1);

    if (ep == -1) {
        ngx_log_error(NGX_LOG_EMERG, cycle->log, ngx_errno,
                      "lua epoll_create() failed");

        return NGX_ERROR;
    }

    return NGX_OK;
}


static ngx_int_t
ngx_http_lua_epoll_set_event(ngx_event_t *ev, ngx_int_t event)
{
    int                  op;
    uint32_t             events, prev;
    ngx_connection_t    *c;
    ngx_event_t         *e;
    struct epoll_event   ee;

    c = ev->data;

    events = (uint32_t) event;

    if (event == NGX_READ_EVENT) {
        e = c->write;
        prev = EPOLLOUT;
#if (NGX_READ_EVENT != EPOLLIN|EPOLLRDHUP)
        events = EPOLLIN|EPOLLRDHUP;
#endif

    } else {
        e = c->read;
        prev = EPOLLIN|EPOLLRDHUP;
#if (NGX_WRITE_EVENT != EPOLLOUT)
        events = EPOLLOUT;
#endif
    }

    if (e->active) {
        op = EPOLL_CTL_MOD;
        events |= prev;

    } else {
        op = EPOLL_CTL_ADD;
    }

    ee.events = events;
    ee.data.ptr = c;

    if (epoll_ctl(ep, op, c->fd, &ee) == -1) {
        ngx_log_error(NGX_LOG_ALERT, ev->log, ngx_errno,
                      "lua epoll_ctl(EPOLL_CTL_ADD, %d) failed, add event: %d",
                      c->fd, events);

        return NGX_ERROR;
    }

    ev->active = 1;

    return NGX_OK;
}


static ngx_int_t
ngx_http_lua_epoll_clear_event(ngx_event_t *ev, ngx_int_t event)
{
    ngx_event_t         *e;
    ngx_connection_t    *c;
    int                  op;
    uint32_t             prev;
    struct epoll_event   ee;

    c = ev->data;

    if (event == NGX_READ_EVENT) {
        e = c->write;
        prev = EPOLLOUT;

    } else {
        e = c->read;
        prev = EPOLLIN|EPOLLRDHUP;
    }

    if (e->active) {
        op = EPOLL_CTL_MOD;
        ee.events = prev;
        ee.data.ptr = c;

    } else {
        op = EPOLL_CTL_DEL;
        ee.events = 0;
        ee.data.ptr = NULL;
    }

    if (epoll_ctl(ep, op, c->fd, &ee) == -1) {
        ngx_log_error(NGX_LOG_ALERT, ev->log, ngx_errno,
                      "lua epoll_ctl(EPOLL_CTL_DEL, %d) failed", c->fd);

        return NGX_ERROR;
    }

    ev->active = 0;

    return NGX_OK;
}


static ngx_int_t
ngx_http_lua_epoll_process_event(ngx_http_request_t *r, ngx_msec_t timer)
{
    int                events;
    uint32_t           revents;
    ngx_err_t          err;
    ngx_event_t       *rev, *wev;
    ngx_connection_t  *c;
    struct epoll_event ee;

    events = epoll_wait(ep, &ee, 1, timer);

    err = (events == -1) ? ngx_errno : 0;

    if (err) {
        ngx_log_error(NGX_LOG_ALERT, r->connection->log, err,
                      "lua epoll_wait() failed");

        return NGX_ERROR;
    }

    if (events == 0) {
        ngx_log_error(NGX_LOG_ALERT, r->connection->log, 0,
                      "lua epoll_wait() returned no events without timeout");

        return NGX_ERROR;
    }

    c = ee.data.ptr;
    revents = ee.events;

    if (revents & (EPOLLERR|EPOLLHUP)) {
        ngx_log_debug2(NGX_LOG_DEBUG_EVENT, r->connection->log, 0,
                       "epoll_wait() error on fd:%d ev:%04XD",
                       c->fd, revents);

        /*
         * if the error events were returned, add EPOLLIN and EPOLLOUT
         * to handle the events at least in one active handler
         */

        revents |= EPOLLIN|EPOLLOUT;
    }

    rev = c->read;

    if ((revents & EPOLLIN) && rev->active) {

#if (NGX_HAVE_EPOLLRDHUP)
        if (revents & EPOLLRDHUP) {
            rev->pending_eof = 1;
        }
#endif

        rev->ready = 1;
        rev->available = -1;
    }

    wev = c->write;

    if ((revents & EPOLLOUT) && wev->active) {
        wev->ready = 1;
#if (NGX_THREADS)
        wev->complete = 1;
#endif
    }

    return NGX_OK;
}
