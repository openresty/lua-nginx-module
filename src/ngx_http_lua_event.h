
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


#define ngx_http_lua_set_event         ngx_http_lua_event_actions.set_event
#define ngx_http_lua_clear_event       ngx_http_lua_event_actions.clear_event
#define ngx_http_lua_process_event     ngx_http_lua_event_actions.process_event


static ngx_inline ngx_int_t
ngx_http_lua_init_event(ngx_cycle_t *cycle)
{
    void              ***ccf;
    ngx_event_conf_t    *ecf;

    ccf = ngx_get_conf(cycle->conf_ctx, ngx_events_module);
    if (ccf == NULL) {
        ngx_log_error(NGX_LOG_EMERG, cycle->log, 0,
                      "no \"events\" section in configuration");

        return NGX_ERROR;
    }

    ecf = (*ccf)[ngx_event_core_module.ctx_index];

#if (NGX_HAVE_EPOLL) && !(NGX_TEST_BUILD_EPOLL)

    if (ngx_strcmp(ecf->name, "epoll") == 0) {
        ngx_http_lua_event_actions = ngx_http_lua_epoll;

    } else

#endif

#if (NGX_HAVE_POLL)

    if (ngx_strcmp(ecf->name, "poll") == 0) {
        ngx_http_lua_event_actions = ngx_http_lua_poll;

    } else

#endif

#if (NGX_HAVE_KQUEUE)

    if (ngx_strcmp(ecf->name, "kqueue") == 0) {
        ngx_http_lua_event_actions = ngx_http_lua_kqueue;

    } else

#endif

    {
        ngx_log_error(NGX_LOG_EMERG, cycle->log, 0,
                      "invalid event type \"%V\"", ecf->name);

        return NGX_ERROR;
    }

    return ngx_http_lua_event_actions.init_event(cycle);
}


#endif /* _NGX_HTTP_LUA_EVENT_H_INCLUDED_ */

/* vi:set ft=c ts=4 sw=4 et fdm=marker: */
