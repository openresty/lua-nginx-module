
/*
 * Copyright (C) Yichun Zhang (agentzh)
 */


#include <ngx_core.h>
#include <ngx_event.h>
#include <ngx_http.h>
#include "../ngx_http_lua_event.h"


static ngx_int_t ngx_http_lua_poll_init_event(ngx_cycle_t *cycle);
static ngx_int_t ngx_http_lua_poll_set_event(ngx_event_t *ev, ngx_int_t event);
static ngx_int_t ngx_http_lua_poll_clear_event(ngx_event_t *ev,
    ngx_int_t event);
static ngx_int_t ngx_http_lua_poll_process_event(ngx_http_request_t *r,
    ngx_msec_t timer);

static struct pollfd   pev;

ngx_http_lua_event_actions_t  ngx_http_lua_poll = {
    ngx_http_lua_poll_init_event,
    ngx_http_lua_poll_set_event,
    ngx_http_lua_poll_clear_event,
    ngx_http_lua_poll_process_event,
};


static ngx_int_t
ngx_http_lua_poll_init_event(ngx_cycle_t *cycle)
{
    return NGX_OK;
}


static ngx_int_t
ngx_http_lua_poll_set_event(ngx_event_t *ev, ngx_int_t event)
{
    ngx_connection_t  *c;

    c = ev->data;

    ev->active = 1;

    if (event == NGX_READ_EVENT) {
#if (NGX_READ_EVENT != POLLIN)
        event = POLLIN;
#endif

    } else {
#if (NGX_WRITE_EVENT != POLLOUT)
        event = POLLOUT;
#endif
    }

    pev.fd = c->fd;
    pev.events = (short) event;
    pev.revents = 0;

    return NGX_OK;
}


static ngx_int_t
ngx_http_lua_poll_clear_event(ngx_event_t *ev, ngx_int_t event)
{
    return NGX_OK;
}


static ngx_int_t
ngx_http_lua_poll_process_event(ngx_http_request_t *r, ngx_msec_t timer)
{
    int                ready, revents;
    ngx_event_t       *ev;
    ngx_err_t          err;
    ngx_connection_t  *c;

    ready = poll(&pev, 1, (int) timer);

    err = (ready == -1) ? ngx_errno : 0;

    if (err) {
        ngx_log_error(NGX_LOG_ALERT, r->connection->log, err,
                      "lua poll() failed");

        return NGX_ERROR;
    }

    if (ready == 0) {
        ngx_log_error(NGX_LOG_ALERT, r->connection->log, 0,
                      "lua poll() returned no events without timeout");

        return NGX_ERROR;
    }

    revents = pev.revents;
    c = ngx_cycle->files[pev.fd];

    if ((revents & POLLIN) && c->read->active) {
        ev = c->read;
        ev->ready = 1;
        ev->available = -1;
    }

    if ((revents & POLLOUT) && c->write->active) {
        ev = c->write;
        ev->ready = 1;
    }

    return NGX_OK;
}
