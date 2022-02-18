
/*
 * Copyright (C) Yichun Zhang (agentzh)
 */


#ifndef _NGX_HTTP_LUA_EVENT_H_INCLUDED_
#define _NGX_HTTP_LUA_EVENT_H_INCLUDED_


#include "ngx_http_lua_common.h"


typedef struct {
    ngx_int_t  (*init_event)(ngx_cycle_t *cycle);
    ngx_int_t  (*set_event)(ngx_event_t *ev, ngx_int_t event);
    ngx_int_t  (*clear_event)(ngx_event_t *ev, ngx_int_t event);
    ngx_int_t  (*process_event)(ngx_http_request_t *r, ngx_msec_t timer);
} ngx_http_lua_event_actions_t;


extern ngx_http_lua_event_actions_t  ngx_http_lua_event_actions;

extern ngx_http_lua_event_actions_t  ngx_http_lua_epoll;
extern ngx_http_lua_event_actions_t  ngx_http_lua_poll;
extern ngx_http_lua_event_actions_t  ngx_http_lua_kqueue;

extern int ngx_http_lua_event_inited;

#define ngx_http_lua_set_event         ngx_http_lua_event_actions.set_event
#define ngx_http_lua_clear_event       ngx_http_lua_event_actions.clear_event
#define ngx_http_lua_process_event     ngx_http_lua_event_actions.process_event


static ngx_inline ngx_int_t
ngx_http_lua_init_event(ngx_cycle_t *cycle)
{
    ngx_module_t        *module;
    ngx_module_t       **modules;
    ngx_event_module_t  *event_module;
    ngx_uint_t           i;
    ngx_connection_t    *c, *next;
    ngx_event_t         *rev, *wev;

    module = NULL;

#if (nginx_version >= 1009011)
    modules = cycle->modules;
#else
    modules = ngx_modules;
#endif

    for (i = 0; modules[i]; i++) {
        if (modules[i]->type != NGX_EVENT_MODULE) {
            continue;
        }

        event_module = modules[i]->ctx;
        if (ngx_strcmp(event_module->name->data, "event_core") == 0)
        {
            continue;
        }

        module = modules[i];
        break;
    }

    if (module == NULL) {
        ngx_log_error(NGX_LOG_EMERG, cycle->log, 0, "no events module found");
        return NGX_ERROR;
    }

    event_module = module->ctx;

    /* FIXME: should init event_module actions here, like:
     * ```
     * if (event_module->actions.init(cycle, ngx_timer_resolution) != NGX_OK) {
     * ```
     *
     * but `epcf` is not initial here before
     * ```
     *  static ngx_int_t
     *  ngx_epoll_init(ngx_cycle_t *cycle, ngx_msec_t timer)
     *  {
     *      ngx_epoll_conf_t  *epcf;
     *
     *      // Segmentation fault below
     *      epcf = ngx_event_get_conf(cycle->conf_ctx, ngx_epoll_module);
     * ```
     */

#if (NGX_HAVE_EPOLL) && !(NGX_TEST_BUILD_EPOLL)

    if (ngx_strcmp(event_module->name->data, "epoll") == 0) {
        ngx_http_lua_event_actions = ngx_http_lua_epoll;

    } else

#endif

#if (NGX_HAVE_POLL)

    if (ngx_strcmp(event_module->name->data, "poll") == 0) {
        ngx_http_lua_event_actions = ngx_http_lua_poll;

    } else

#endif

#if (NGX_HAVE_KQUEUE)

    if (ngx_strcmp(event_module->name->data, "kqueue") == 0) {
        ngx_http_lua_event_actions = ngx_http_lua_kqueue;

    } else

#endif

    {
        return NGX_ERROR;
    }

    cycle->connection_n = 128;
    cycle->connections =
        ngx_alloc(sizeof(ngx_connection_t) * cycle->connection_n, cycle->log);
    if (cycle->connections == NULL) {
        return NGX_ERROR;
    }

    c = cycle->connections;

    cycle->read_events = ngx_alloc(sizeof(ngx_event_t) * cycle->connection_n,
                                   cycle->log);
    if (cycle->read_events == NULL) {
        return NGX_ERROR;
    }

    rev = cycle->read_events;
    for (i = 0; i < cycle->connection_n; i++) {
        rev[i].closed = 1;
        rev[i].instance = 1;
    }

    cycle->write_events = ngx_alloc(sizeof(ngx_event_t) * cycle->connection_n,
                                    cycle->log);
    if (cycle->write_events == NULL) {
        return NGX_ERROR;
    }

    wev = cycle->write_events;
    for (i = 0; i < cycle->connection_n; i++) {
        wev[i].closed = 1;
    }

    i = cycle->connection_n;
    next = NULL;

    do {
        i--;

        c[i].data = next;
        c[i].read = &cycle->read_events[i];
        c[i].write = &cycle->write_events[i];
        c[i].fd = (ngx_socket_t) -1;

        next = &c[i];
    } while (i);

    cycle->free_connections = next;
    cycle->free_connection_n = cycle->connection_n;

    return ngx_http_lua_event_actions.init_event(cycle);
}


#endif /* _NGX_HTTP_LUA_EVENT_H_INCLUDED_ */

/* vi:set ft=c ts=4 sw=4 et fdm=marker: */
