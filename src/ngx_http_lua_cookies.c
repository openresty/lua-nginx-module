
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

static int
ngx_http_lua_ngx_req_get_cookies(lua_State *L) {
    ngx_array_t                  *cookies;
    ngx_table_elt_t              **cookie;
    u_char                       *start, *end;
    u_char                       *key_start, *value_start;
    u_char                       *elem_start;
    int                          value_len, key_len, total_len, elem_len;
    int                          narray;
    u_char                       *curr;
    ngx_http_request_t           *r;
    int                           i, j, k;
    int                           table_idx;
    int                           contain_multi_value;
    int                           n;
    int                           max;
    int                           count = 0;

    n = lua_gettop(L);

    if (n >= 1) {
        if (lua_isnil(L, 1)) {
            max = NGX_HTTP_LUA_MAX_HEADERS;

        } else {
            max = luaL_checkinteger(L, 1);
        }

    } else {
        max = NGX_HTTP_LUA_MAX_HEADERS;
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
        key_start = start;
        total_len = 0;
        /* trim leading spaces*/
        while (start < end && *start == ' ') {
            start++;
        }
        while (start < end) {
            if ((start == end-1) || ((*start == ';' || *start  == ','))) {
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
                    if ((start == end-1) && (*start != ';')  && (*start != '=')){
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
                    value_len = total_len - 1 - key_len; 

                    if ((start == end-1) && (*start != ';')){
                        value_len += 1;
                    }

                    if (value_len == 0) {
                        lua_pushliteral(L,  "");
                        ngx_http_lua_set_multi_value_table(L, -3);

                    } else {
                        contain_multi_value = 0; 
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
                                    lua_pushlstring(L, (char *) elem_start, elem_len+1);

                                } else {
                                    lua_pushlstring(L, (char *) elem_start, elem_len);
                                }
                                narray++;
                                elem_start = curr+1; 
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
                            for (k = 1; k < narray; k++) {
                                lua_rawseti(L, table_idx++, k);
                            }
                            lua_settable(L, -3);

                        } else {
                            ngx_http_lua_set_multi_value_table(L, -3);
                        }
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
        }

        ngx_log_debug2(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                       "lua request cookie: \"%V: %V\"",
                       &cookie[i]->key, &cookie[i]->value);

        if (max > 0 && ++count == max) {
            ngx_log_debug1(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                           "lua hit request cookie limit %d", max);

            return 1;
        }
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
