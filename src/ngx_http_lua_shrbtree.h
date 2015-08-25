
/*
 * Copyright (C) helloyi
 */


#ifndef _NGX_HTTP_LUA_SHRBTREE_H_INCLUDED_
#define _NGX_HTTP_LUA_SHRBTREE_H_INCLUDED_


#include "ngx_http_lua_common.h"

typedef struct ngx_http_lua_shrbtree_ltable_s ngx_http_lua_shrbtree_ltable_t;
typedef struct ngx_http_lua_shrbtree_node_s ngx_http_lua_shrbtree_node_t;

/* talbe start*/
typedef ngx_http_lua_shrbtree_node_t ngx_http_lua_shrbtree_lfield_t;

struct ngx_http_lua_shrbtree_ltable_s {
  ngx_rbtree_t rbtree;
  ngx_rbtree_node_t sentinel;
  ngx_http_lua_shrbtree_ltable_t *metatable;
};
/* talbe end*/

typedef union ngx_http_lua_shrbtree_lvalue_s {
  lua_Number n;
  ngx_http_lua_shrbtree_ltable_t t;
  char *s;
} ngx_http_lua_shrbtree_lvalue_t;


/* START rbtree node */
struct ngx_http_lua_shrbtree_node_s {
  size_t klen;
  size_t vlen;
  u_char ktype;
  u_char vtype;
  u_char data; /* lua_Integer/lua_Number/string/ltable */
};
/* END rbtree node*/

typedef struct {
  ngx_rbtree_t                  rbtree;
  ngx_rbtree_node_t             sentinel;
} ngx_http_lua_shrbtree_shctx_t;

typedef struct {
    ngx_http_lua_shrbtree_shctx_t  *sh;
    ngx_slab_pool_t              *shpool;
    ngx_str_t                     name;
    ngx_http_lua_main_conf_t     *main_conf;
    ngx_log_t                    *log;
} ngx_http_lua_shrbtree_ctx_t;


#define ngx_http_lua_module_shrbtree (ngx_http_lua_module.spare1)

ngx_int_t ngx_http_lua_shrbtree_init_zone(ngx_shm_zone_t *shm_zone, void *data);
void ngx_http_lua_shrbtree_rbtree_insert_value(ngx_rbtree_node_t *node1,
                                               ngx_rbtree_node_t *node2,
                                               ngx_rbtree_node_t *sentinel);
void ngx_http_lua_inject_shrbtree_api(ngx_http_lua_main_conf_t *lmcf,
                                      lua_State *L);


#endif /* _NGX_HTTP_LUA_SHRBTREE_H_INCLUDED_ */

/* vi:set ft=c ts=4 sw=4 et fdm=marker: */
