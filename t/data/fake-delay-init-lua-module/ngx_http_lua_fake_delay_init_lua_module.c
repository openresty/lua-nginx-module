#include <ngx_config.h>
#include <ngx_core.h>
#include <ngx_http.h>
#include <nginx.h>


#include <lua.h>
#include <lualib.h>
#include <lauxlib.h>


#include "ngx_http_lua_api.h"


static void *ngx_http_lua_fake_delay_init_lua_create_main_conf(ngx_conf_t *cf);
static ngx_int_t ngx_http_lua_fake_delay_init_lua_init(ngx_conf_t *cf);

static char *ngx_http_lua_fake_delay_init_lua(ngx_conf_t *cf,
    ngx_command_t *cmd, void *conf);
static ngx_int_t ngx_http_lua_fake_delay_init_lua_init_zone(
    ngx_shm_zone_t *shm_zone, void *data);
static int ngx_http_lua_fake_delay_init_lua_preload(lua_State *L);
static int ngx_http_lua_fake_delay_init_lua_get_info(lua_State *L);


typedef struct {
    ngx_array_t     *shm_zones;
    ngx_uint_t       shm_zone_inited;
} ngx_http_lua_fake_delay_init_lua_main_conf_t;


static ngx_command_t ngx_http_lua_fake_delay_init_lua_cmds[] = {

    { ngx_string("lua_fake_delay_shm"),
      NGX_HTTP_MAIN_CONF|NGX_CONF_TAKE2,
      ngx_http_lua_fake_delay_init_lua,
      0,
      0,
      NULL },

    ngx_null_command
};


static ngx_http_module_t  ngx_http_lua_fake_delay_init_lua_module_ctx = {
    NULL,                                   /* preconfiguration */
    ngx_http_lua_fake_delay_init_lua_init,  /* postconfiguration */

    /* create main configuration */
    ngx_http_lua_fake_delay_init_lua_create_main_conf,
    NULL,                                   /* init main configuration */

    NULL,                                   /* create server configuration */
    NULL,                                   /* merge server configuration */

    NULL,                                   /* create location configuration */
    NULL,                                   /* merge location configuration */
};


ngx_module_t  ngx_http_lua_fake_delay_init_lua_module = {
    NGX_MODULE_V1,
    &ngx_http_lua_fake_delay_init_lua_module_ctx, /* module context */
    ngx_http_lua_fake_delay_init_lua_cmds,        /* module directives */
    NGX_HTTP_MODULE,                   /* module type */
    NULL,                              /* init master */
    NULL,                              /* init module */
    NULL,                              /* init process */
    NULL,                              /* init thread */
    NULL,                              /* exit thread */
    NULL,                              /* exit process */
    NULL,                              /* exit master */
    NGX_MODULE_V1_PADDING
};


typedef struct {
    ngx_str_t   name;
    size_t      size;

    ngx_http_lua_fake_delay_init_lua_main_conf_t *lfdilcf;
    volatile ngx_cycle_t                         *cycle;
} ngx_http_lua_fake_delay_init_lua_ctx_t;


static void *
ngx_http_lua_fake_delay_init_lua_create_main_conf(ngx_conf_t *cf)
{
    ngx_http_lua_fake_delay_init_lua_main_conf_t *lfdilcf;

    /*
     * shm_zone_inited = 0
     */
    lfdilcf = ngx_pcalloc(cf->pool, sizeof(*lfdilcf));
    if (lfdilcf == NULL) {
        return NULL;
    }

    return lfdilcf;
}


static char *
ngx_http_lua_fake_delay_init_lua(ngx_conf_t *cf, ngx_command_t *cmd,
    void *conf)
{
    ngx_http_lua_fake_delay_init_lua_main_conf_t   *lfdilcf = conf;
    ngx_http_lua_fake_delay_init_lua_ctx_t         *ctx;

    ngx_str_t                   *value, name;
    ngx_shm_zone_t              *zone;
    ngx_shm_zone_t             **zp;
    ssize_t                      size;
    ngx_int_t                    rc;

    if (lfdilcf->shm_zones == NULL) {
        lfdilcf->shm_zones = ngx_palloc(cf->pool, sizeof(ngx_array_t));
        if (lfdilcf->shm_zones == NULL) {
            return NGX_CONF_ERROR;
        }

        if (ngx_array_init(lfdilcf->shm_zones, cf->pool, 2,
                           sizeof(ngx_shm_zone_t *))
            != NGX_OK)
        {
            return NGX_CONF_ERROR;
        }
    }

    value = cf->args->elts;

    ctx = NULL;

    if (value[1].len == 0) {
        ngx_conf_log_error(NGX_LOG_EMERG, cf, 0,
                           "invalid lua fake_delay_shm name \"%V\"", &value[1]);
        return NGX_CONF_ERROR;
    }

    name = value[1];

    size = ngx_parse_size(&value[2]);

    if (size <= 8191) {
        ngx_conf_log_error(NGX_LOG_EMERG, cf, 0,
                           "invalid lua fake_delay_shm size \"%V\"", &value[2]);
        return NGX_CONF_ERROR;
    }

    ctx = ngx_pcalloc(cf->pool,
                      sizeof(ngx_http_lua_fake_delay_init_lua_ctx_t));
    if (ctx == NULL) {
        return NGX_CONF_ERROR;
    }

    ctx->name = name;
    ctx->size = size;
    ctx->lfdilcf = lfdilcf;
    ctx->cycle = cf->cycle;

    zone = ngx_shared_memory_add(cf, &name, (size_t) size,
                                 &ngx_http_lua_fake_delay_init_lua_module);
    if (zone == NULL) {
        return NGX_CONF_ERROR;
    }

    if (zone->data) {
        ctx = zone->data;

        ngx_conf_log_error(NGX_LOG_EMERG, cf, 0,
                           "lua_fake_shm \"%V\" is already defined as "
                           "\"%V\"", &name, &ctx->name);
        return NGX_CONF_ERROR;
    }

    zone->init = ngx_http_lua_fake_delay_init_lua_init_zone;
    zone->data = ctx;

    zp = ngx_array_push(lfdilcf->shm_zones);
    if (zp == NULL) {
        return NGX_CONF_ERROR;
    }

    *zp = zone;

    rc = ngx_http_lua_delay_init_declare(cf,
             &ngx_http_lua_fake_delay_init_lua_module);
    if (rc == NGX_ERROR) {
        return NGX_CONF_ERROR;
    }

    return NGX_CONF_OK;
}


/*
 * must run after init_by_lua
 */
static ngx_int_t
ngx_http_lua_fake_delay_init_lua_init_zone(ngx_shm_zone_t *shm_zone,
    void *data)
{
    ngx_http_lua_fake_delay_init_lua_main_conf_t   *lfdilcf;
    ngx_http_lua_fake_delay_init_lua_ctx_t         *ctx;
    ngx_int_t                                       rc;
    volatile ngx_cycle_t                           *saved_cycle;

    ctx = shm_zone->data;

    lfdilcf = ctx->lfdilcf;

    lfdilcf->shm_zone_inited++;
    if (lfdilcf->shm_zone_inited == lfdilcf->shm_zones->nelts){
        saved_cycle = ngx_cycle;
        ngx_cycle = ctx->cycle;

        rc = ngx_http_lua_delay_init_handler();

        ngx_cycle = saved_cycle;

        if (rc != NGX_OK) {
            return NGX_ERROR;
        }
    }

    return NGX_OK;
}


static ngx_int_t
ngx_http_lua_fake_delay_init_lua_init(ngx_conf_t *cf)
{
    ngx_http_lua_add_package_preload(cf, "fake_delay_init_lua",
        ngx_http_lua_fake_delay_init_lua_preload);
    return NGX_OK;
}


static int
ngx_http_lua_fake_delay_init_lua_preload(lua_State *L)
{
    ngx_http_lua_fake_delay_init_lua_main_conf_t *lfdilcf;
    ngx_http_conf_ctx_t               *hmcf_ctx;
    ngx_cycle_t                       *cycle;

    ngx_uint_t                   i;
    ngx_shm_zone_t             **zone;

    lua_getglobal(L, "__ngx_cycle");
    cycle = lua_touserdata(L, -1);
    lua_pop(L, 1);

    hmcf_ctx = (ngx_http_conf_ctx_t *) cycle->conf_ctx[ngx_http_module.index];
    lfdilcf =
        hmcf_ctx->main_conf[ngx_http_lua_fake_delay_init_lua_module.ctx_index];

    if (lfdilcf->shm_zones != NULL) {
        lua_createtable(L, 0, lfdilcf->shm_zones->nelts /* nrec */);

        lua_createtable(L, 0 /* narr */, 2 /* nrec */); /* shared mt */

        lua_pushcfunction(L, ngx_http_lua_fake_delay_init_lua_get_info);
        lua_setfield(L, -2, "get_info");

        lua_pushvalue(L, -1); /* shared mt mt */
        lua_setfield(L, -2, "__index"); /* shared mt */

        zone = lfdilcf->shm_zones->elts;

        for (i = 0; i < lfdilcf->shm_zones->nelts; i++) {
            lua_pushlstring(L, (char *) zone[i]->shm.name.data,
                            zone[i]->shm.name.len);

            /* shared mt key */

            lua_createtable(L, 1 /* narr */, 0 /* nrec */);
                /* table of zone[i] */
            lua_pushlightuserdata(L, zone[i]); /* shared mt key ud */
            lua_rawseti(L, -2, 1); /* {zone[i]} */
            lua_pushvalue(L, -3); /* shared mt key ud mt */
            lua_setmetatable(L, -2); /* shared mt key ud */
            lua_rawset(L, -4); /* shared mt */
        }

        lua_pop(L, 1); /* shared */

    } else {
        lua_newtable(L);    /* ngx.shared */
    }

    return 1;
}


static int
ngx_http_lua_fake_delay_init_lua_get_info(lua_State *L)
{
    ngx_int_t                    n;
    ngx_shm_zone_t              *zone;

    n = lua_gettop(L);

    if (n != 1) {
        return luaL_error(L, "expecting exactly one arguments, "
                          "but only seen %d", n);
    }

    luaL_checktype(L, 1, LUA_TTABLE);

    lua_rawgeti(L, 1, 1);
    zone = lua_touserdata(L, -1);
    lua_pop(L, 1);

    if (zone == NULL) {
        return luaL_error(L, "bad \"zone\" argument");
    }

    lua_pushlstring(L, (char *) zone->shm.name.data, zone->shm.name.len);
    lua_pushnumber(L, zone->shm.size);

    return 2;
}
