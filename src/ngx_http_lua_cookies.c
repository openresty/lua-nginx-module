
/*
 * Copyright (C) Xiaozhe Wang (chaoslawful)
 * Copyright (C) Yichun Zhang (agentzh)
 */


#ifndef DDEBUG
#define DDEBUG 0
#endif
#include "ddebug.h"


#include "ngx_http_lua_cookies.h"
#include "ngx_http_lua_util.h"


static int ngx_http_lua_ngx_req_get_cookies(lua_State *L);
static int ngx_http_lua_ngx_cookie_parser(lua_State *L, u_char *start, u_char *end, int max, ngx_http_request_t *r);
static int ngx_http_lua_ngx_cookie_process_value(lua_State *L, u_char *value_start,  int value_len);



static int
ngx_http_lua_ngx_cookie_process_value(lua_State *L, u_char *value_start,  int value_len) {
    int                           contain_multi_value = 0;
    u_char                       *curr;
    u_char                       *elem_start;
    int                           j, k, elem_len;
    int                           narray;
    int                           table_idx;
    curr = value_start;
    elem_start = value_start;
    j = 0;
    narray = 1;
    elem_len = 0;
    while (j < value_len) {
        if ((*curr == '&'  &&  j != value_len - 1) || j == value_len - 1) {
            if (*curr == '&') {
                contain_multi_value = 1;
            }
            if (j == value_len - 1) {
                lua_pushlstring(L, (char *) elem_start, elem_len + 1);

            } else {
                lua_pushlstring(L, (char *) elem_start, elem_len);
            }
            narray++;
            elem_start = curr + 1;
            elem_len = 0;

        } else {
            elem_len++;
        }
        curr++;
        j++;
    }
    if (contain_multi_value) {
        lua_createtable(L, narray, 0);
        table_idx = -narray;
        lua_insert(L, table_idx);
        for (k = narray-1; k > 0 ; k--) {
            lua_rawseti(L, table_idx++, k);
        }
        lua_settable(L, -3);

    } else {
        ngx_http_lua_set_multi_value_table(L, -3);
    }
    return contain_multi_value;
}


static int
ngx_http_lua_ngx_cookie_parser(lua_State *L, u_char *start,  u_char *end, int max,  ngx_http_request_t *r) {
    u_char                       *key_start, *value_start;
    u_char                       *curr;
    int                           value_len, key_len, total_len;
    int                           cookie_num;
    int                           count = 0;
    key_start = start;
    total_len = 0;
    while (start < end) {
        if ((start == end - 1) || ((*start == ';' || *start  == ','))) {
            key_len = 0;
            /* while (key_start < end && *key_start == ' ') {
                key_start++;
            } */
            curr = key_start;
            while (*curr != '=') {
                key_len++;
                if (key_len >= total_len) {
                    break;
                }
                curr++;
            }

            if (key_len >= total_len) {
                if ((start == end - 1) && (*start != ';')  && (*start != '=')){
                    key_len += 1;
                }
                lua_pushlstring(L, (char *) key_start, key_len);

                if (*start == '=')
                    lua_pushliteral(L,  "");
                else
                    lua_pushboolean(L, 1);

                ngx_http_lua_set_multi_value_table(L, -3);

            } else {
                lua_pushlstring(L, (char *) key_start, key_len);
                value_start = curr + 1;
                /* while (value_start < end && *value_start == ' ') {
                    value_start++;
                } */
                value_len = total_len - key_len - 1;

                if (start == end - 1 && *start != ';'){
                    value_len += 1;
                }

                if (value_len == 0) {
                    lua_pushliteral(L,  "");
                    ngx_http_lua_set_multi_value_table(L, -3);

                } else {
                    ngx_http_lua_ngx_cookie_process_value(L, value_start, value_len);
                }
            }

            start++;
            while (start < end && *start == ' ') {
                start++;
            }
            key_start = start;
            key_len = 0;
            value_len = 0;
            total_len = 0;

        } else {
            start++;
            total_len++;
        }

        if (max > 0 && ++count == max) {
            ngx_log_debug1(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                           "lua hit request cookie limit %d", max);
            return 1;
        }
    }
    return 1;
}

static int
ngx_http_lua_ngx_req_get_cookies(lua_State *L) {
    ngx_array_t                  *cookies;
    ngx_table_elt_t              **cookie;
    int                           i;
    int                           n;
    ngx_http_request_t           *r;
    int                           max;
    u_char                       *start, *end;

    n = lua_gettop(L);

    if (n >= 1) {
        if (lua_isnil(L, 1)) {
            max = NGX_HTTP_LUA_MAX_COOKIES;

        } else {
            max = luaL_checkinteger(L, 1);
        }

    } else {
        max = NGX_HTTP_LUA_MAX_COOKIES;
    }

    r = ngx_http_lua_get_req(L);
    if (r == NULL) {
        return luaL_error(L, "no request object found");
    }

    ngx_http_lua_check_fake_request(L, r);

    lua_createtable(L, 0, 4);

    cookies = &r->headers_in.cookies;
    cookie = cookies->elts;

    for (i = 0; i < cookies->nelts; i++) {

        start = cookie[i]->value.data;
        end = cookie[i]->value.data + cookie[i]->value.len;
        /* trim leading spaces*/
        while (start < end && *start == ' ') {
            start++;
        }
        ngx_http_lua_ngx_cookie_parser(L, start, end, max, r);
        ngx_log_debug2(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                       "lua request cookie: \"%V: %V\"",
                        &cookie[i]->key, &cookie[i]->value);
    }

    return 1;
}


void
ngx_http_lua_inject_req_cookie_api(ngx_log_t *log, lua_State *L)
{
    lua_pushcfunction(L, ngx_http_lua_ngx_req_get_cookies);
    lua_setfield(L, -2, "get_cookies");
}

/* vi:set ft=c ts=4 sw=4 et fdm=marker: */
