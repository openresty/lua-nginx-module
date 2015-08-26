
/*
 * Copyright (C) helloyi
 */


#ifndef DDEBUG
#define DDEBUG 0
#endif
#include "ddebug.h"


#include "ngx_http_lua_shrbtree.h"
#include "ngx_http_lua_util.h"
#include "ngx_http_lua_api.h"


ngx_int_t ngx_http_lua_shrbtree_init_zone(ngx_shm_zone_t *shm_zone,
                                          void *data);
void ngx_http_lua_inject_shrbtree_api(ngx_http_lua_main_conf_t *lmcf,
                                      lua_State *L);
void ngx_http_lua_shrbtree_rbtree_insert_value(ngx_rbtree_node_t *node1,
                                               ngx_rbtree_node_t *node2,
                                               ngx_rbtree_node_t *sentinel);

/* START declare of pushlvalue */
static void ngx_http_lua_shrbtree_pushlvalue(lua_State *L,
                                             u_char *data,
                                             u_char type,
                                             size_t len);
static void ngx_http_lua_shrbtree_pushltable(lua_State *L,
                                             ngx_http_lua_shrbtree_ltable_t *ltable);
static void ngx_http_lua_shrbtree_pushlfield(lua_State *L,
                                             ngx_rbtree_node_t *node,
                                             ngx_rbtree_node_t *sentinel);
/* END declare of pushlvalue */


/* START declare of tolvalue */
static ngx_int_t
ngx_http_lua_shrbtree_tolvalue(lua_State *L, int index,
                               u_char **data,
                               u_char *type, size_t *len);
static ngx_int_t
ngx_http_lua_shrbtree_toltable(lua_State *L,
                               int index,
                               ngx_http_lua_shrbtree_ltable_t *ltable);
/* END declare of tolvalue */


/* START declare of get */
static int ngx_http_lua_shrbtree_get(lua_State *L);
static void
ngx_http_lua_shrbtree_get_node(lua_State *L,
                               ngx_http_lua_shrbtree_ctx_t *ctx,
                               ngx_http_lua_shrbtree_node_t **srbtnp,
                               ngx_rbtree_node_t **nodep);
static void
ngx_http_lua_shrbtree_get_lfield(ngx_http_lua_shrbtree_ltable_t *ltable,
                                 void *kdata, size_t klen,
                                 ngx_http_lua_shrbtree_lfield_t **lfieldp);
/* END declare of get */

/* START declare of insert */
static int ngx_http_lua_shrbtree_insert(lua_State *L);
static void ngx_http_lua_shrbtree_insert_real(lua_State *L,
                                              ngx_http_lua_shrbtree_ctx_t *ctx,
                                              ngx_rbtree_node_t *node);
/* END declare of insert */

static int ngx_http_lua_shrbtree_delete(lua_State *L);

static int ngx_http_lua_shrbtree_luaL_checknarg(lua_State *L, int narg);

static ngx_shm_zone_t*
ngx_http_lua_shrbtree_luaL_checkzone(lua_State *L, int arg);

#define NGX_HTTP_LUA_SHRBTREE_LVALUE_SIZE sizeof(ngx_http_lua_shrbtree_lvalue_t)

ngx_int_t
ngx_http_lua_shrbtree_init_zone(ngx_shm_zone_t *shm_zone, void *data)
{
    ngx_http_lua_shrbtree_ctx_t  *octx = data;

    size_t                      len;
    ngx_http_lua_shrbtree_ctx_t  *ctx;
    ngx_http_lua_main_conf_t   *lmcf;

    dd("init zone");

    ctx = shm_zone->data;

    if (octx) {
        ctx->sh = octx->sh;
        ctx->shpool = octx->shpool;

        goto done;
    }

    ctx->shpool = (ngx_slab_pool_t *) shm_zone->shm.addr;

    if (shm_zone->shm.exists) {
        ctx->sh = ctx->shpool->data;

        goto done;
    }

    ctx->sh = ngx_slab_alloc(ctx->shpool, sizeof(ngx_http_lua_shrbtree_shctx_t));
    if (ctx->sh == NULL) {
        return NGX_ERROR;
    }

    ctx->shpool->data = ctx->sh;

    ngx_rbtree_init(&ctx->sh->rbtree, &ctx->sh->sentinel,
                    ngx_http_lua_shrbtree_rbtree_insert_value);

    len = sizeof(" in lua_shared_rbtree_zone \"\"") + shm_zone->shm.name.len;

    ctx->shpool->log_ctx = ngx_slab_alloc(ctx->shpool, len);
    if (ctx->shpool->log_ctx == NULL) {
        return NGX_ERROR;
    }

    ngx_sprintf(ctx->shpool->log_ctx, " in lua_shared_rbtree_zone \"%V\"%Z",
                &shm_zone->shm.name);

#if defined(nginx_version) && nginx_version >= 1005013
    ctx->shpool->log_nomem = 0;
#endif

done:

    dd("get lmcf");

    lmcf = ctx->main_conf;

    dd("lmcf->lua: %p", lmcf->lua);

    lmcf->shm_zones_inited++;

    if (lmcf->shm_zones_inited == lmcf->shm_zones->nelts
        && lmcf->init_handler)
    {
        if (lmcf->init_handler(ctx->log, lmcf, lmcf->lua) != NGX_OK) {
            /* an error happened */
            return NGX_ERROR;
        }
    }

    return NGX_OK;
}

void
ngx_http_lua_inject_shrbtree_api(ngx_http_lua_main_conf_t *lmcf, lua_State *L)
{
    ngx_http_lua_shrbtree_ctx_t   *ctx;
    ngx_uint_t                   i;
    ngx_shm_zone_t             **zone;

    lua_createtable(L, 0 /* narr */, 4 /* nrec */); /* {zone[i]} mt */

    lua_pushcfunction(L, ngx_http_lua_shrbtree_get);
    lua_setfield(L, -2, "get");

    lua_pushcfunction(L, ngx_http_lua_shrbtree_insert);
    lua_setfield(L, -2, "insert");

    lua_pushcfunction(L, ngx_http_lua_shrbtree_delete);
    lua_setfield(L, -2, "delete");

    lua_pushvalue(L, -1);
    lua_setfield(L, -2, "__index");

    zone = lmcf->shm_zones->elts;

    for (i = 0; i < lmcf->shm_zones->nelts; i++) {
        if (zone[i]->tag != (void *)&ngx_http_lua_module_shrbtree) {
            continue;
        }
        ctx = zone[i]->data;

        lua_pushlstring(L, (char *) ctx->name.data, ctx->name.len);
        lua_createtable(L, 1 /* narr */, 0 /* nrec */);
        lua_pushlightuserdata(L, zone[i]);
        lua_rawseti(L, -2, 1); /* {zone[i]} */
        lua_pushvalue(L, -3);  /* mt of {zone[i]}*/
        lua_setmetatable(L, -2);
        lua_rawset(L, -4);
    }

    lua_pop(L, 1);
}

static int
ngx_http_lua_shrbtree_luaL_checknarg(lua_State *L, int narg)
{
    if (narg == lua_gettop(L)) {return 0;}

    lua_Debug ar;
    if (!lua_getstack(L, 0, &ar)) { /* no stack frame? */
        return luaL_error(L, "excpected %d %s", narg,
                          1 == narg ? "argument" : "arguments");
    }
    lua_getinfo(L, "n", &ar);
    if (ar.name == NULL) {
        ar.name = "?";
    }
    return luaL_error(L, "excpected %d %s to '%s'",
                      narg,
                      1 == narg ? "argument" : "arguments",
                      ar.name);
}

static ngx_shm_zone_t*
ngx_http_lua_shrbtree_luaL_checkzone(lua_State *L, int arg)
{
    ngx_shm_zone_t *zone;

    lua_rawgeti(L, arg, 1);
    zone = lua_touserdata(L, -1);
    lua_pop(L, 1);
    if (zone == NULL) {
        luaL_argerror(L, arg, "excpected \"zone\"");
    }

    return zone;
}

/* START ngx_http_lua_shrbtree api */
static int
ngx_http_lua_shrbtree_get(lua_State *L)
{
    ngx_int_t                      rc, n;
    ngx_http_lua_shrbtree_ctx_t    *ctx;
    ngx_http_lua_shrbtree_node_t   *srbtn;
    ngx_http_lua_shrbtree_ltable_t *ltable;
    ngx_http_lua_shrbtree_lfield_t *lfield;
    ngx_shm_zone_t                 *zone;

    u_char key[NGX_HTTP_LUA_SHRBTREE_LVALUE_SIZE];
    u_char *kdata = &key[0];
    u_char ktype;
    size_t klen;

    ngx_int_t is_getlfield = 0;

    /* [{zone}, {key, [field, cmpf}]*/
    ngx_http_lua_shrbtree_luaL_checknarg(L, 2 /* narg */);
    luaL_checktype(L, 1, LUA_TTABLE);
    luaL_checktype(L, 2, LUA_TTABLE);
    luaL_argcheck(L, 1 == lua_objlen(L, 1), 1, "expected 1 element");

    n = lua_objlen(L, 2);
    luaL_argcheck(L, 2 == n || 3 == n, 2, "expected 2 or 3 elements");
    if (3 == n) {is_getlfield = 1;}

    zone = ngx_http_lua_shrbtree_luaL_checkzone(L, 1);
    ctx = zone->data;

    ngx_shmtx_lock(&ctx->shpool->mutex);
    ngx_http_lua_shrbtree_get_node(L, ctx, &srbtn, NULL);
    if (NULL == srbtn) {
        ngx_shmtx_unlock(&ctx->shpool->mutex);
        lua_pushnil(L);
        lua_pushliteral(L, "no exists");
        return 2;
    }

    if (!is_getlfield) {
        ngx_http_lua_shrbtree_pushlvalue(L, (&srbtn->data) + srbtn->klen,
                                         srbtn->vtype, srbtn->vlen);
        ngx_shmtx_unlock(&ctx->shpool->mutex);
        return 1;
    }

/* getfield */
    if (LUA_TTABLE != srbtn->vtype) {
        ngx_shmtx_unlock(&ctx->shpool->mutex);
        lua_pushnil(L);
        lua_pushliteral(L, "the value type isn't a table");
        return 2;
    }

    /* field */
    lua_rawgeti(L, 2, 2);
    rc = ngx_http_lua_shrbtree_tolvalue(L, -1, &kdata, &ktype, &klen);
    if (0 != rc) {return rc;}
    ltable = (ngx_http_lua_shrbtree_ltable_t *)((&srbtn->data) + srbtn->klen);
    ngx_http_lua_shrbtree_get_lfield(ltable, kdata, klen, &lfield);

    if (NULL == lfield) {
        ngx_shmtx_unlock(&ctx->shpool->mutex);
        lua_pushnil(L);
        lua_pushliteral(L, "no exists this field");
        return 2;
    }

    ngx_http_lua_shrbtree_pushlvalue(L, &lfield->data + lfield->klen,
                                     lfield->vtype, lfield->vlen);
    ngx_shmtx_unlock(&ctx->shpool->mutex);
    return 1;
}

static int
ngx_http_lua_shrbtree_insert(lua_State *L)
{
    ngx_int_t                    n, rc;
    ngx_shm_zone_t               *zone;
    ngx_http_lua_shrbtree_ctx_t  *ctx;
    ngx_rbtree_node_t            *node;
    ngx_http_lua_shrbtree_node_t *srbtn;
    u_char key[NGX_HTTP_LUA_SHRBTREE_LVALUE_SIZE];
    u_char value[NGX_HTTP_LUA_SHRBTREE_LVALUE_SIZE];
    u_char *kdata = &key[0];
    u_char *vdata = &value[0];
    size_t klen, vlen;
    u_char ktype, vtype;
    void *p;

    ngx_http_lua_shrbtree_luaL_checknarg(L, 2);
    luaL_checktype(L, 1, LUA_TTABLE);
    luaL_checktype(L, 2, LUA_TTABLE);
    luaL_argcheck(L, 1 == lua_objlen(L, 1), 1, "expected 1 element");
    luaL_argcheck(L, 3 == lua_objlen(L, 2), 2, "expected 3 elements");

    zone = ngx_http_lua_shrbtree_luaL_checkzone(L, 1);

    ctx = zone->data;

    /* {key, value, cmpf} */
    lua_rawgeti(L, 2, 1); /* key */
    rc = ngx_http_lua_shrbtree_tolvalue(L, -1, &kdata, &ktype, &klen);
    if (0 != rc) {return rc;}

    lua_rawgeti(L, 2, 2); /* value */
    rc = ngx_http_lua_shrbtree_tolvalue(L, -1, &vdata, &vtype, &vlen);
    if (0 != rc) {return rc;}

    /* start node alloc*/
    n = offsetof(ngx_rbtree_node_t, data)
      + offsetof(ngx_http_lua_shrbtree_node_t, data)
      + klen
      + vlen;

    ngx_shmtx_lock(&ctx->shpool->mutex);
    node = ngx_slab_alloc_locked(ctx->shpool, n);

    if (node == NULL) {
        ngx_shmtx_unlock(&ctx->shpool->mutex);

        lua_pushboolean(L, 0);
        lua_pushliteral(L, "no memory");
        return 2;
    }
    /* end node alloc*/

    /* start insert */
    srbtn = (ngx_http_lua_shrbtree_node_t *)&node->data;

    srbtn->ktype = ktype;
    srbtn->vtype = vtype;
    srbtn->klen = klen;
    srbtn->vlen = vlen;
    p = ngx_copy(&srbtn->data, kdata, klen);
    ngx_memcpy(p, vdata, vlen);

    lua_pop(L, 2);

    ngx_http_lua_shrbtree_insert_real(L, ctx, node);
    ngx_shmtx_unlock(&ctx->shpool->mutex);
    /* end insert */

    lua_pushboolean(L, 1);
    return 1;
}
/* END ngx_http_lua_shrbtree api*/

/* START get helper */
static void
ngx_http_lua_shrbtree_get_lfield(ngx_http_lua_shrbtree_ltable_t *ltable,
                                 void *kdata,
                                 size_t klen,
                                 ngx_http_lua_shrbtree_lfield_t **lfieldp)
{
    ngx_int_t                      rc;
    ngx_rbtree_node_t              *node, *sentinel;
    ngx_http_lua_shrbtree_lfield_t *lfield;
    uint32_t  hash;

    node = ltable->rbtree.root;
    sentinel = ltable->rbtree.sentinel;
    hash = ngx_crc32_short(kdata, klen);

    while (node != sentinel) {

        if (hash < node->key) {
            node = node->left;
            continue;
        }

        if (hash > node->key) {
            node = node->right;
            continue;
        }

        /* hash == node->key */
        lfield = (ngx_http_lua_shrbtree_lfield_t *) &node->data;

        rc = ngx_memn2cmp(kdata, &lfield->data, klen, (size_t)lfield->klen);

        if (rc == 0) {
            *lfieldp = lfield;
            return;
        }

        node = (rc < 0) ? node->left : node->right;
    }

    *lfieldp = NULL;
}

static void
ngx_http_lua_shrbtree_get_node(lua_State *L,
                               ngx_http_lua_shrbtree_ctx_t *ctx,
                               ngx_http_lua_shrbtree_node_t **srbtnp,
                               ngx_rbtree_node_t **nodep)
{
    ngx_int_t                    rc;
    ngx_rbtree_node_t            *node, *sentinel;
    ngx_http_lua_shrbtree_node_t *srbtn;
    ngx_int_t cmpf_index;

    node = ctx->sh->rbtree.root;
    sentinel = ctx->sh->rbtree.sentinel;

    cmpf_index = lua_objlen(L, 2);
    while (node != sentinel) {
        /* start call cmpf of lua*/
        lua_rawgeti(L, 2, cmpf_index);
        lua_rawgeti(L, 2, 1);
        srbtn = (ngx_http_lua_shrbtree_node_t *)&node->data;
        ngx_http_lua_shrbtree_pushlvalue(L, &srbtn->data, srbtn->ktype, srbtn->klen);
        lua_call(L, 2, 1);
        /* end call cmpf of lua*/

        rc = (ngx_int_t)lua_tonumber(L, -1);
        lua_pop(L, 1);
        if (0 == rc) {
            if (srbtnp) *srbtnp = srbtn;
            if (nodep)  *nodep = node;
            return;
        }

        node = (rc < 0) ? node->left : node->right;
    }

    if (srbtnp) *srbtnp = NULL;
    if (nodep)  *nodep = NULL;
}

/* END get helper */

/* START insert helper */
void
ngx_http_lua_shrbtree_rbtree_insert_value(ngx_rbtree_node_t *node1,
                                          ngx_rbtree_node_t *node2,
                                          ngx_rbtree_node_t *sentinel)
{
    /* nothing to do, */
    return;
}


static void
ngx_http_lua_shrbtree_insert_real(lua_State *L,
                                  ngx_http_lua_shrbtree_ctx_t *ctx,
                                  ngx_rbtree_node_t *node)
{
    ngx_int_t                    rc;
    ngx_rbtree_node_t            **root, *temp, *sentinel;
    ngx_rbtree_node_t            **p;
    ngx_http_lua_shrbtree_node_t *srbtn;

    root = &ctx->sh->rbtree.root;
    temp = *root;
    sentinel = ctx->sh->rbtree.sentinel;

    if (*root == sentinel) {
        node->parent = NULL;
        node->left = sentinel;
        node->right = sentinel;
        ngx_rbt_black(node);
        *root = node;

        return;
    }

    /* [zone, {key, value, cmpf}] */
    for (;;) {
        /* start call cmpf of lua */
        lua_rawgeti(L, 2, 3);
        lua_rawgeti(L, 2, 1);
        srbtn = (ngx_http_lua_shrbtree_node_t *)&temp->data;
        ngx_http_lua_shrbtree_pushlvalue(L, &srbtn->data, srbtn->ktype, srbtn->klen);
        lua_call(L, 2, 1);
        /* end call cmpf of lua*/

        rc = (ngx_int_t)lua_tonumber(L, -1);
        lua_pop(L, 1);
        if (0 > rc) {
            p = &temp->left;

        } else if (0 < rc) {
            p = &temp->right;

        } else {
            return;
        }

        if (*p == sentinel) {
            break;
        }

        temp = *p;
    }

    *p = node;
    node->parent = temp;
    node->left = sentinel;
    node->right = sentinel;
    ngx_rbt_red(node);

    ngx_rbtree_insert(&ctx->sh->rbtree, node);
}
/* END insert helper */


/* START pushlvalue */
static void
ngx_http_lua_shrbtree_pushlvalue(lua_State *L,
                                 u_char *data,
                                 u_char type,
                                 size_t len)
{
    switch (type) {
    case LUA_TBOOLEAN:
        lua_pushboolean(L, *(int *)data);
        break;
    case LUA_TNUMBER:
        lua_pushnumber(L, *(lua_Number *)data);
        break;
    case LUA_TSTRING:
        lua_pushlstring(L, (char *)data, len);
        break;
    case LUA_TTABLE:
        ngx_http_lua_shrbtree_pushltable(L, (ngx_http_lua_shrbtree_ltable_t *)data);
        break;
    default:
        luaL_error(L, "bad type of value");
    }
}

static void
ngx_http_lua_shrbtree_pushltable(lua_State *L,
                                 ngx_http_lua_shrbtree_ltable_t *ltable)
{
    ngx_rbtree_node_t *root = ltable->rbtree.root;
    ngx_rbtree_node_t *sentinel = ltable->rbtree.sentinel;
    lua_newtable(L);
    ngx_http_lua_shrbtree_pushlfield(L, root, sentinel);
    // metatable
}

static void
ngx_http_lua_shrbtree_pushlfield(lua_State *L,
                                 ngx_rbtree_node_t *node,
                                 ngx_rbtree_node_t *sentinel)
{
    ngx_http_lua_shrbtree_lfield_t *lfield;

    if (node == sentinel) return;

    lfield = (ngx_http_lua_shrbtree_lfield_t *)&node->data;
    ngx_http_lua_shrbtree_pushlvalue(L, &lfield->data,
                                     lfield->ktype, lfield->klen);
    ngx_http_lua_shrbtree_pushlvalue(L, &lfield->data + lfield->klen,
                                     lfield->vtype, lfield->vlen);
    lua_settable(L, -3);

    ngx_http_lua_shrbtree_pushlfield(L, node->left, sentinel);
    ngx_http_lua_shrbtree_pushlfield(L, node->right, sentinel);
}
/*END pushlvalue */

/* START tolvalue */
static ngx_int_t
ngx_http_lua_shrbtree_tolvalue(lua_State *L,
                               int index,
                               u_char **data,
                               u_char *type,
                               size_t *len)
{

    ngx_http_lua_shrbtree_ltable_t *ltable;

    switch (lua_type(L, index)) {
    case LUA_TBOOLEAN:
        *type = LUA_TBOOLEAN;
        *(int *)(*data) = lua_toboolean(L, index);
        *len = sizeof(int);
        break;

    case LUA_TNUMBER:
        *type = LUA_TNUMBER;
        *(lua_Number *)(*data) = lua_tonumber(L, index);
        *len = sizeof(lua_Number);
        break;

    case LUA_TSTRING:
        *type = LUA_TSTRING;
        *data = (u_char *)lua_tolstring(L, index, len);
        break;

    case LUA_TTABLE:
        *type = LUA_TTABLE;
        ltable = (ngx_http_lua_shrbtree_ltable_t *)(*data);
        ngx_rbtree_init(&ltable->rbtree,
                        &ltable->sentinel,
                        ngx_rbtree_insert_value);

        *len = sizeof(ngx_http_lua_shrbtree_ltable_t);
        return ngx_http_lua_shrbtree_toltable(L, index, ltable);

    default:
        return luaL_error(L, "bad type value");
    }
    return 0;
}

static ngx_int_t
ngx_http_lua_shrbtree_toltable(lua_State *L,
                               int index,
                               ngx_http_lua_shrbtree_ltable_t *ltable)
{
    ngx_shm_zone_t              *zone;
    ngx_http_lua_shrbtree_ctx_t *ctx;
    ngx_rbtree_node_t           *node;
    ngx_http_lua_shrbtree_lfield_t *lfield;
    void *p;

    u_char key[NGX_HTTP_LUA_SHRBTREE_LVALUE_SIZE];
    u_char value[NGX_HTTP_LUA_SHRBTREE_LVALUE_SIZE];
    u_char *kdata = &key[0];
    u_char *vdata = &value[0];
    int rc, n;
    size_t klen, vlen;
    u_char ktype, vtype;

    zone = ngx_http_lua_shrbtree_luaL_checkzone(L, 1);
    ctx = zone->data;

    lua_pushnil(L);
    if (index < 0) {
        index -= 1;
    }
    while (lua_next(L, index)) {
        rc = ngx_http_lua_shrbtree_tolvalue(L, -2, &kdata, &ktype, &klen);
        if (0 != rc) {return rc;}
        rc = ngx_http_lua_shrbtree_tolvalue(L, -1, &vdata, &vtype, &vlen);
        if (0 != rc) {return rc;}

        /* start alloc*/
        n = offsetof(ngx_rbtree_node_t, data)
          + offsetof(ngx_http_lua_shrbtree_lfield_t, data)
          + klen
          + vlen;

        ngx_shmtx_lock(&ctx->shpool->mutex);
        node = (ngx_rbtree_node_t *)ngx_slab_alloc_locked(ctx->shpool, n);

        if (node == NULL) {
            ngx_shmtx_unlock(&ctx->shpool->mutex);
            lua_pushnil(L);
            lua_pushliteral(L, "no memory");
            return 2;
        }
        /* end alloc*/

        /* start insert*/
        /* copy data */
        lfield = (ngx_http_lua_shrbtree_lfield_t *)&node->data;

        lfield->ktype = ktype;
        lfield->vtype = vtype;
        lfield->klen = klen;
        lfield->vlen = vlen;
        p = ngx_copy(&lfield->data, kdata, klen);
        ngx_memcpy(p, vdata, vlen);
        node->key = ngx_crc32_short((u_char *)kdata, klen);
        /* end copy data */

        ngx_rbtree_insert(&ltable->rbtree, node);
        ngx_shmtx_unlock(&ctx->shpool->mutex);
        /* end insert*/
        lua_pop(L, 1);
    }

    return 0;
}
/* END tolvalue */

static int
ngx_http_lua_shrbtree_delete(lua_State *L)
{
    ngx_shm_zone_t               *zone;
    ngx_http_lua_shrbtree_ctx_t  *ctx;
    ngx_rbtree_node_t            *node;

    ngx_http_lua_shrbtree_luaL_checknarg(L, 2);
    luaL_checktype(L, 1, LUA_TTABLE);
    luaL_checktype(L, 2, LUA_TTABLE);
    luaL_argcheck(L, 1 == lua_objlen(L, 1), 1, "expected 1 elements");
    luaL_argcheck(L, 2 == lua_objlen(L, 2), 2, "expected 2 elements");

    zone = ngx_http_lua_shrbtree_luaL_checkzone(L, 1);
    ctx = zone->data;

    ngx_shmtx_lock(&ctx->shpool->mutex);
    ngx_http_lua_shrbtree_get_node(L, ctx, NULL, &node);
    if (NULL == node) {
        ngx_shmtx_unlock(&ctx->shpool->mutex);
        lua_pushboolean(L, 0);
        lua_pushliteral(L, "no exists");
        return 2;
    }

    ngx_rbtree_delete(&ctx->sh->rbtree, node);
    ngx_slab_free_locked(ctx->shpool, node);
    ngx_shmtx_unlock(&ctx->shpool->mutex);

    lua_pushboolean(L, 1);
    return 1;
}
