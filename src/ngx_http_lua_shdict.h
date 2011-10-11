#ifndef NGX_HTTP_LUA_SHDICT_H
#define NGX_HTTP_LUA_SHDICT_H


#include "ngx_http_lua_common.h"


typedef struct {
    u_char                       color;
    u_char                       dummy;
    u_short                      key_len;
    ngx_queue_t                  queue;
    ngx_msec_t                   expires;
    int                          value_type;
    u_short                      value_len;
    u_char                       data[1];
} ngx_http_lua_shdict_node_t;


typedef struct {
    ngx_rbtree_t                  rbtree;
    ngx_rbtree_node_t             sentinel;
    ngx_queue_t                   queue;
} ngx_http_lua_shdict_shctx_t;


typedef struct {
    ngx_http_lua_shdict_shctx_t  *sh;
    ngx_slab_pool_t              *shpool;
    ngx_str_t                     name;
} ngx_http_lua_shdict_ctx_t;


ngx_int_t ngx_http_lua_shdict_init_zone(ngx_shm_zone_t *shm_zone, void *data);

void ngx_http_lua_shdict_rbtree_insert_value(ngx_rbtree_node_t *temp,
    ngx_rbtree_node_t *node, ngx_rbtree_node_t *sentinel);

ngx_int_t ngx_http_lua_shdict_lookup(ngx_shm_zone_t *shm_zone, ngx_uint_t hash,
    u_char *kdata, size_t klen, ngx_uint_t *ep, int *vtype, u_char **vdata,
    size_t *vlen);

void ngx_http_lua_shdict_expire(ngx_http_lua_shdict_ctx_t *ctx, ngx_uint_t n);


#endif /* NGX_HTTP_LUA_SHDICT_H */

