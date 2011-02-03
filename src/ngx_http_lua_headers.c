/* vim:set ft=c ts=4 sw=4 et fdm=marker: */
/* Copyright (C) agentzh */

#define DDEBUG 0

#include "ddebug.h"

#include "ngx_http_lua_headers.h"
#include "ngx_http_lua_util.h"
#include <ctype.h>

/* request time */

static ngx_int_t ngx_http_set_header(ngx_http_request_t *r,
    ngx_http_lua_header_val_t *hv, ngx_str_t *value);

static ngx_int_t ngx_http_set_header_helper(ngx_http_request_t *r,
    ngx_http_lua_header_val_t *hv, ngx_str_t *value,
    ngx_table_elt_t **output_header, ngx_flag_t no_create);

static ngx_int_t ngx_http_set_builtin_header(ngx_http_request_t *r,
    ngx_http_lua_header_val_t *hv, ngx_str_t *value);

static ngx_int_t ngx_http_set_content_length_header(ngx_http_request_t *r,
    ngx_http_lua_header_val_t *hv, ngx_str_t *value);

static ngx_int_t ngx_http_set_content_type_header(ngx_http_request_t *r,
        ngx_http_lua_header_val_t *hv, ngx_str_t *value);

static ngx_int_t ngx_http_clear_builtin_header(ngx_http_request_t *r,
    ngx_http_lua_header_val_t *hv, ngx_str_t *value);

static ngx_int_t ngx_http_clear_content_length_header(ngx_http_request_t *r,
        ngx_http_lua_header_val_t *hv, ngx_str_t *value);


static ngx_http_lua_set_header_t ngx_http_lua_set_handlers[] = {

    { ngx_string("Server"),
                 offsetof(ngx_http_headers_out_t, server),
                 ngx_http_set_builtin_header },

    { ngx_string("Date"),
                 offsetof(ngx_http_headers_out_t, date),
                 ngx_http_set_builtin_header },

    { ngx_string("Content-Encoding"),
                 offsetof(ngx_http_headers_out_t, content_encoding),
                 ngx_http_set_builtin_header },

    { ngx_string("Location"),
                 offsetof(ngx_http_headers_out_t, location),
                 ngx_http_set_builtin_header },

    { ngx_string("Refresh"),
                 offsetof(ngx_http_headers_out_t, refresh),
                 ngx_http_set_builtin_header },

    { ngx_string("Last-Modified"),
                 offsetof(ngx_http_headers_out_t, last_modified),
                 ngx_http_set_builtin_header },

    { ngx_string("Content-Range"),
                 offsetof(ngx_http_headers_out_t, content_range),
                 ngx_http_set_builtin_header },

    { ngx_string("Accept-Ranges"),
                 offsetof(ngx_http_headers_out_t, accept_ranges),
                 ngx_http_set_builtin_header },

    { ngx_string("WWW-Authenticate"),
                 offsetof(ngx_http_headers_out_t, www_authenticate),
                 ngx_http_set_builtin_header },

    { ngx_string("Expires"),
                 offsetof(ngx_http_headers_out_t, expires),
                 ngx_http_set_builtin_header },

    { ngx_string("E-Tag"),
                 offsetof(ngx_http_headers_out_t, etag),
                 ngx_http_set_builtin_header },

    { ngx_string("Content-Length"),
                 offsetof(ngx_http_headers_out_t, content_length),
                 ngx_http_set_content_length_header },

    { ngx_string("Content-Type"),
                 0,
                 ngx_http_set_content_type_header },

    { ngx_null_string, 0, ngx_http_set_header }
};


/* request time implementation */

static ngx_int_t
ngx_http_set_header(ngx_http_request_t *r, ngx_http_lua_header_val_t *hv,
        ngx_str_t *value)
{
    return ngx_http_set_header_helper(r, hv, value, NULL, 0);
}


static ngx_int_t
ngx_http_set_header_helper(ngx_http_request_t *r, ngx_http_lua_header_val_t *hv,
        ngx_str_t *value, ngx_table_elt_t **output_header,
        ngx_flag_t no_create)
{
    ngx_table_elt_t             *h;
    ngx_list_part_t             *part;
    ngx_uint_t                  i;
    ngx_flag_t                  matched = 0;

    if (hv->no_override) {
        goto new_header;
    }

    part = &r->headers_out.headers.part;
    h = part->elts;

    for (i = 0; /* void */; i++) {
        if (i >= part->nelts) {
            if (part->next == NULL) {
                break;
            }
            part = part->next;
            h = part->elts;
            i = 0;
        }

        if (
            (h[i].key.len == hv->key.len
                && ngx_strncasecmp(h[i].key.data,
                    hv->key.data,
                                   h[i].key.len) == 0)
            ||
            (h[i].key.len >= hv->key.len-1
                && ngx_strncasecmp(h[i].key.data,
                    hv->key.data,
                                   hv->key.len-1) == 0)
            )
        {
            if (value->len == 0) {
                dd("clearing normal header for %.*s", (int) hv->key.len,
                        hv->key.data);

                h[i].hash = 0;
            }

            h[i].value = *value;

            if (output_header) {
                *output_header = &h[i];
            }

            /* return NGX_OK; */
            matched = 1;
        }
    }

    if (matched){
      return NGX_OK;
    }

    if (no_create && value->len == 0) {
        return NGX_OK;
    }

new_header:
    h = ngx_list_push(&r->headers_out.headers);

    if (h == NULL) {
        return NGX_HTTP_INTERNAL_SERVER_ERROR;
    }

    if (value->len == 0) {
        h->hash = 0;
    } else {
        h->hash = hv->hash;
    }

    h->key = hv->key;
    h->value = *value;

    h->lowcase_key = ngx_pnalloc(r->pool, h->key.len);
    if (h->lowcase_key == NULL) {
        return NGX_HTTP_INTERNAL_SERVER_ERROR;
    }

    ngx_strlow(h->lowcase_key, h->key.data, h->key.len);

    if (output_header) {
        *output_header = h;
    }

    return NGX_OK;
}


static ngx_int_t
ngx_http_set_builtin_header(ngx_http_request_t *r,
        ngx_http_lua_header_val_t *hv, ngx_str_t *value)
{
    ngx_table_elt_t  *h, **old;

    if (hv->offset) {
        old = (ngx_table_elt_t **) ((char *) &r->headers_out + hv->offset);

    } else {
        old = NULL;
    }

    if (old == NULL || *old == NULL) {
        return ngx_http_set_header_helper(r, hv, value, old, 0);
    }

    h = *old;

    if (value->len == 0) {
        dd("clearing the builtin header");

        h->hash = 0;
        h->value = *value;

        return NGX_OK;
    }

    h->hash = hv->hash;
    h->key = hv->key;
    h->value = *value;

    return NGX_OK;
}


static ngx_int_t
ngx_http_set_content_type_header(ngx_http_request_t *r,
        ngx_http_lua_header_val_t *hv, ngx_str_t *value)
{
    r->headers_out.content_type_len = value->len;
    r->headers_out.content_type = *value;
    r->headers_out.content_type_hash = hv->hash;
    r->headers_out.content_type_lowcase = NULL;

    value->len = 0;

    return ngx_http_set_header_helper(r, hv, value, NULL, 1);
}


static ngx_int_t
ngx_http_set_content_length_header(ngx_http_request_t *r,
        ngx_http_lua_header_val_t *hv, ngx_str_t *value)
{
    off_t           len;

    if (value->len == 0) {
        return ngx_http_clear_content_length_header(r, hv, value);
    }

    len = ngx_atosz(value->data, value->len);
    if (len == NGX_ERROR) {
        return NGX_ERROR;
    }

    r->headers_out.content_length_n = len;

    return ngx_http_set_builtin_header(r, hv, value);
}


static ngx_int_t
ngx_http_clear_content_length_header(ngx_http_request_t *r,
        ngx_http_lua_header_val_t *hv, ngx_str_t *value)
{
    r->headers_out.content_length_n = -1;

    return ngx_http_clear_builtin_header(r, hv, value);
}


static ngx_int_t
ngx_http_clear_builtin_header(ngx_http_request_t *r,
        ngx_http_lua_header_val_t *hv, ngx_str_t *value)
{
    value->len = 0;

    return ngx_http_set_builtin_header(r, hv, value);
}


ngx_int_t
ngx_http_lua_set_header(ngx_http_request_t *r, ngx_str_t key, ngx_str_t value,
        ngx_flag_t override)
{
    ngx_http_lua_header_val_t         hv;
    ngx_http_lua_set_header_t        *handlers = ngx_http_lua_set_handlers;

    ngx_uint_t                        i;

    dd("set header value: %.*s", (int) value.len, value.data);

    hv.hash = 1;
    hv.key = key;

    hv.offset = 0;
    hv.no_override = ! override;

    for (i = 0; handlers[i].name.len; i++) {
        if (hv.key.len != handlers[i].name.len
                || ngx_strncasecmp(hv.key.data, handlers[i].name.data,
                    handlers[i].name.len) != 0)
        {
            dd("hv key comparison: %s <> %s", handlers[i].name.data,
                    hv.key.data);

            continue;
        }

        dd("Matched handler: %s %s", handlers[i].name.data, hv.key.data);

        hv.offset = handlers[i].offset;
        hv.handler = handlers[i].handler;

        break;
    }

    if (handlers[i].name.len == 0 && handlers[i].handler) {
        hv.offset = handlers[i].offset;
        hv.handler = handlers[i].handler;
    }

    return hv.handler(r, &hv, &value);
}

