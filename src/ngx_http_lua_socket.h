#ifndef NGX_HTTP_LUA_SOCKET_H
#define NGX_HTTP_LUA_SOCKET_H


#include "ngx_http_lua_common.h"

typedef struct ngx_http_lua_socket_upstream_s  ngx_http_lua_socket_upstream_t;


typedef
    int (*ngx_http_lua_socket_retval_handler)(ngx_http_request_t *r,
        ngx_http_lua_socket_upstream_t *u, lua_State *L);


typedef void (*ngx_http_lua_socket_upstream_handler_pt)(ngx_http_request_t *r,
    ngx_http_lua_socket_upstream_t *u);


struct ngx_http_lua_socket_upstream_s {
    ngx_http_lua_socket_retval_handler          prepare_retvals;
    ngx_http_lua_socket_upstream_handler_pt     read_event_handler;
    ngx_http_lua_socket_upstream_handler_pt     write_event_handler;

    ngx_http_lua_loc_conf_t         *conf;
    ngx_http_cleanup_pt             *cleanup;
    ngx_http_request_t              *request;
    ngx_peer_connection_t            peer;

    ngx_http_upstream_resolved_t    *resolved;

    ngx_buf_t                        buffer;
    size_t                           length;
    size_t                           rest;

    ngx_uint_t                       ft_type;
    ngx_err_t                        socket_errno;

    ngx_output_chain_ctx_t           output;
    ngx_chain_writer_ctx_t           writer;

    ngx_chain_t                     *free_bufs;
    ngx_chain_t                     *busy_bufs;

    luaL_Buffer                      luabuf;

    ngx_int_t                      (*input_filter)(void *data, ssize_t bytes);
    void                            *input_filter_ctx;

    ssize_t                          recv_bytes;
    size_t                           request_len;
    ngx_chain_t                     *request_bufs;

    unsigned                         luabuf_inited:1;
    unsigned                         request_sent:1;

    unsigned                         waiting:1;
    unsigned                         eof:1;
};


void ngx_http_lua_inject_socket_api(lua_State *L);


#endif /* NGX_HTTP_LUA_SOCKET_H */

