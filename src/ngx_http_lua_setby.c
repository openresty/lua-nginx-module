/* vim:set ft=c ts=4 sw=4 et fdm=marker: */

#ifndef DDEBUG
#define DDEBUG 0
#endif
#include "ddebug.h"

#include "ngx_http_lua_setby.h"
#include "ngx_http_lua_exception.h"
#include "ngx_http_lua_util.h"
#include "ngx_http_lua_pcrefix.h"
#include "ngx_http_lua_time.h"
#include "ngx_http_lua_log.h"
#include "ngx_http_lua_regex.h"
#include "ngx_http_lua_ndk.h"
#include "ngx_http_lua_variable.h"
#include "ngx_http_lua_string.h"
#include "ngx_http_lua_misc.h"
#include "ngx_http_lua_consts.h"
#include "ngx_http_lua_shdict.h"


#if !(defined(NDK) && NDK)
#define ngx_http_lua_script_exit  ((u_char *) &ngx_http_lua_script_exit_code)


typedef struct {
    ngx_http_script_code_pt     code;
    void                       *func;
    size_t                      size;
    void                       *data;
} ngx_http_lua_var_filter_code_t;


typedef struct {
    ngx_array_t                *codes;        /* uintptr_t */
    ngx_uint_t                  stack_size;
    ngx_flag_t                  log;
    ngx_flag_t                  uninitialized_variable_warn;
} ngx_http_lua_rewrite_loc_conf_t;


typedef ngx_int_t (*ngx_http_lua_var_filter_pt)(ngx_http_request_t *r,
    ngx_str_t *val, ngx_http_variable_value_t *v, void *data);


static ngx_int_t ngx_http_lua_rewrite_var(ngx_http_request_t *r,
        ngx_http_variable_value_t *v, uintptr_t data);
static void ngx_http_lua_multi_value_filter_code(ngx_http_script_engine_t *e);
static char *ngx_http_lua_set_var_filter(ngx_conf_t *cf,
        ngx_http_lua_rewrite_loc_conf_t *rlcf,
        ngx_http_lua_var_filter_t *filter);
static char *ngx_http_lua_rewrite_value(ngx_conf_t *cf,
        ngx_http_lua_rewrite_loc_conf_t *lcf, ngx_str_t *value);


uintptr_t ngx_http_lua_script_exit_code = (uintptr_t) NULL;
#endif


static void ngx_http_lua_inject_arg_api(lua_State *L,
       size_t nargs,  ngx_http_variable_value_t *args);
static int ngx_http_lua_param_get(lua_State *L);
static void ngx_http_lua_set_by_lua_env(lua_State *L, ngx_http_request_t *r,
        size_t nargs, ngx_http_variable_value_t *args);


ngx_int_t
ngx_http_lua_set_by_chunk(lua_State *L, ngx_http_request_t *r, ngx_str_t *val,
        ngx_http_variable_value_t *args, size_t nargs)
{
    size_t           i;
    ngx_int_t        rc;
    u_char          *err_msg;
    size_t           rlen;
    u_char          *rdata;
#if (NGX_PCRE)
    ngx_pool_t      *old_pool;
#endif

    ngx_http_lua_ctx_t          *ctx;
    ngx_http_cleanup_t          *cln;

    ctx = ngx_http_get_module_ctx(r, ngx_http_lua_module);

    if (ctx == NULL) {
        ctx = ngx_pcalloc(r->pool, sizeof(ngx_http_lua_ctx_t));
        if (ctx == NULL) {
            return NGX_ERROR;
        }

        dd("setting new ctx: ctx = %p", ctx);

        ctx->cc_ref = LUA_NOREF;
        ctx->ctx_ref = LUA_NOREF;

        ngx_http_set_ctx(r, ctx, ngx_http_lua_module);

    } else {
        ngx_http_lua_reset_ctx(r, L, ctx);
    }

    if (ctx->cleanup == NULL) {
        cln = ngx_http_cleanup_add(r, 0);
        if (cln == NULL) {
            return NGX_ERROR;
        }

        cln->handler = ngx_http_lua_request_cleanup;
        cln->data = r;
        ctx->cleanup = &cln->handler;
    }

    /*  set Lua VM panic handler */
    lua_atpanic(L, ngx_http_lua_atpanic);

    /*  initialize nginx context in Lua VM, code chunk at stack top    sp = 1 */
    ngx_http_lua_set_by_lua_env(L, r, nargs, args);

    /*  passing directive arguments to the user code */
    for (i = 0; i < nargs; i++) {
        lua_pushlstring(L, (const char *) args[i].data, args[i].len);
    }

#if (NGX_PCRE)
    /* XXX: work-around to nginx regex subsystem */
    old_pool = ngx_http_lua_pcre_malloc_init(r->pool);
#endif

    /*  protected call user code */
    rc = lua_pcall(L, nargs, 1, 0);

#if (NGX_PCRE)
    /* XXX: work-around to nginx regex subsystem */
    ngx_http_lua_pcre_malloc_done(old_pool);
#endif

    if (rc != 0) {
        /*  error occured when running loaded code */
        err_msg = (u_char *) lua_tostring(L, -1);

        if (err_msg != NULL) {
            ngx_log_error(NGX_LOG_ERR, r->connection->log, 0, "(lua-error) %s",
                    err_msg);

            lua_settop(L, 0);    /*  clear remaining elems on stack */
        }

        return NGX_ERROR;
    }

    NGX_LUA_EXCEPTION_TRY {
        rdata = (u_char *) lua_tolstring(L, -1, &rlen);

        if (rdata) {
            val->data = ngx_pcalloc(r->pool, rlen);
            if (val->data == NULL) {
                return NGX_ERROR;
            }

            ngx_memcpy(val->data, rdata, rlen);
            val->len = rlen;

        } else {
            val->data = NULL;
            val->len = 0;
        }

    } NGX_LUA_EXCEPTION_CATCH {
        dd("nginx execution restored");
    }

    /*  clear Lua stack */
    lua_settop(L, 0);

    return NGX_OK;
}


static void
ngx_http_lua_inject_arg_api(lua_State *L, size_t nargs,
        ngx_http_variable_value_t *args)
{
    lua_newtable(L);    /*  .arg table aka {} */

    lua_newtable(L);    /*  the metatable for new param table */
    lua_pushinteger(L, nargs);    /*  1st upvalue: argument number */
    lua_pushlightuserdata(L, args);    /*  2nd upvalue: pointer to arguments */

    lua_pushcclosure(L, ngx_http_lua_param_get, 2);
        /*  binding upvalues to __index meta-method closure */

    lua_setfield(L, -2, "__index");
    lua_setmetatable(L, -2);    /*  tie the metatable to param table */

    lua_setfield(L, -2, "arg");    /*  set ngx.arg table */
}


static int
ngx_http_lua_param_get(lua_State *L)
{
    int         idx;
    int         n;

    ngx_http_variable_value_t       *v;

    idx = luaL_checkint(L, 2);

    /*  get number of args from closure */
    n = luaL_checkint(L, lua_upvalueindex(1));

    /*  get args from closure */
    v = lua_touserdata(L, lua_upvalueindex(2));

    if (idx < 0 || idx > n-1) {
        lua_pushnil(L);

    } else {
        lua_pushlstring(L, (const char *) (v[idx].data), v[idx].len);
    }

    return 1;
}


/**
 * Set environment table for the given code closure.
 *
 * Before:
 *         | code closure | <- top
 *         |      ...     |
 *
 * After:
 *         | code closure | <- top
 *         |      ...     |
 * */
static void
ngx_http_lua_set_by_lua_env(lua_State *L, ngx_http_request_t *r, size_t nargs,
        ngx_http_variable_value_t *args)
{
    ngx_http_lua_main_conf_t    *lmcf;

    lmcf = ngx_http_get_module_main_conf(r, ngx_http_lua_module);

    /*  set nginx request pointer to current lua thread's globals table */
    lua_pushlightuserdata(L, r);
    lua_setglobal(L, GLOBALS_SYMBOL_REQUEST);

    /**
     * we want to create empty environment for current script
     *
     * setmetatable({}, {__index = _G})
     *
     * if a function or symbol is not defined in our env, __index will lookup
     * in the global env.
     *
     * all variables created in the script-env will be thrown away at the end
     * of the script run.
     * */
    lua_newtable(L);    /*  new empty environment aka {} */

#if defined(NDK) && NDK
    ngx_http_lua_inject_ndk_api(L);
#endif /* defined(NDK) && NDK */

    /*  {{{ initialize ngx.* namespace */

    lua_createtable(L, 0 /* narr */, 71 /* nrec */);    /*  ngx.* */

    ngx_http_lua_inject_internal_utils(r->connection->log, L);

    ngx_http_lua_inject_core_consts(L);
    ngx_http_lua_inject_http_consts(L);

    ngx_http_lua_inject_log_api(L);
    ngx_http_lua_inject_http_consts(L);
    ngx_http_lua_inject_core_consts(L);
    ngx_http_lua_inject_time_api(L);
    ngx_http_lua_inject_string_api(L);
    ngx_http_lua_inject_variable_api(L);
    ngx_http_lua_inject_req_api_no_io(r->connection->log, L);
    ngx_http_lua_inject_arg_api(L, nargs, args);
#if (NGX_PCRE)
    ngx_http_lua_inject_regex_api(L);
#endif
    ngx_http_lua_inject_shdict_api(lmcf, L);
    ngx_http_lua_inject_misc_api(L);

    lua_setfield(L, -2, "ngx");
    /*  }}} */

    /*  {{{ make new env inheriting main thread's globals table */
    lua_newtable(L);    /*  the metatable for the new env */
    lua_pushvalue(L, LUA_GLOBALSINDEX);
    lua_setfield(L, -2, "__index");
    lua_setmetatable(L, -2);    /*  setmetatable({}, {__index = _G}) */
    /*  }}} */

    lua_setfenv(L, -2);    /*  set new running env for the code closure */
}


#if !(defined(NDK) && NDK)
static ngx_int_t
ngx_http_lua_rewrite_var(ngx_http_request_t *r, ngx_http_variable_value_t *v,
    uintptr_t data)
{
    ngx_http_variable_t              *var;
    ngx_http_core_main_conf_t        *cmcf;
    ngx_http_lua_rewrite_loc_conf_t  *rlcf;

    rlcf = ngx_http_get_module_loc_conf(r, ngx_http_rewrite_module);

    if (rlcf->uninitialized_variable_warn == 0) {
        *v = ngx_http_variable_null_value;
        return NGX_OK;
    }

    cmcf = ngx_http_get_module_main_conf(r, ngx_http_core_module);

    var = cmcf->variables.elts;

    /*
     * the ngx_http_rewrite_module sets variables directly in r->variables,
     * and they should be handled by ngx_http_get_indexed_variable(),
     * so the handler is called only if the variable is not initialized
     */

    ngx_log_error(NGX_LOG_WARN, r->connection->log, 0,
                  "using uninitialized \"%V\" variable", &var[data].name);

    *v = ngx_http_variable_null_value;

    return  NGX_OK;
}


static void
ngx_http_lua_multi_value_filter_code(ngx_http_script_engine_t *e)
{
    ngx_int_t                        rc;
    ngx_str_t                        str;
    ngx_http_variable_value_t       *v;
    ngx_http_lua_var_filter_pt       func;
    ngx_http_lua_var_filter_code_t  *vfc;

    vfc = (ngx_http_lua_var_filter_code_t *) e->ip;

    e->ip += sizeof(ngx_http_lua_var_filter_code_t);

    v = e->sp - vfc->size;
    e->sp = v + 1;

    func = vfc->func;

    rc = func(e->request, &str, v, vfc->data);

    switch (rc) {

    case NGX_OK :

        v->data = str.data;
        v->len = str.len;
        v->valid = 1;
        v->no_cacheable = 0;
        v->not_found = 0;

        ngx_log_debug1(NGX_LOG_DEBUG_HTTP, e->request->connection->log, 0,
                        "http script value (post filter): \"%v\"", v);
        break;

    case NGX_DECLINED :

        v->valid = 0;
        v->not_found = 1;
        v->no_cacheable = 1;

        break;

    case NGX_ERROR :

        e->ip = ngx_http_lua_script_exit;
        e->status = NGX_HTTP_INTERNAL_SERVER_ERROR;
        break;
    }
}


static char *
ngx_http_lua_set_var_filter(ngx_conf_t *cf,
        ngx_http_lua_rewrite_loc_conf_t *rlcf,
        ngx_http_lua_var_filter_t *filter)
{
    ngx_http_lua_var_filter_code_t   *vfc;

    vfc = ngx_http_script_start_code(cf->pool, &rlcf->codes,
                                     sizeof(ngx_http_lua_var_filter_code_t));
    if (vfc == NULL) {
        return NGX_CONF_ERROR;
    }

    vfc->code = ngx_http_lua_multi_value_filter_code;
    vfc->func = filter->func;
    vfc->size = filter->size;
    vfc->data = filter->data;

    return  NGX_CONF_OK;
}


static char *
ngx_http_lua_rewrite_value(ngx_conf_t *cf,
        ngx_http_lua_rewrite_loc_conf_t *lcf, ngx_str_t *value)
{
    ngx_int_t                              n;
    ngx_http_script_compile_t              sc;
    ngx_http_script_value_code_t          *val;
    ngx_http_script_complex_value_code_t  *complex;

    n = ngx_http_script_variables_count(value);

    if (n == 0) {
        val = ngx_http_script_start_code(cf->pool, &lcf->codes,
                                         sizeof(ngx_http_script_value_code_t));
        if (val == NULL) {
            return NGX_CONF_ERROR;
        }

        n = ngx_atoi(value->data, value->len);

        if (n == NGX_ERROR) {
            n = 0;
        }

        val->code = ngx_http_script_value_code;
        val->value = (uintptr_t) n;
        val->text_len = (uintptr_t) value->len;
        val->text_data = (uintptr_t) value->data;

        return NGX_CONF_OK;
    }

    complex = ngx_http_script_start_code(cf->pool, &lcf->codes,
                                 sizeof(ngx_http_script_complex_value_code_t));
    if (complex == NULL) {
        return NGX_CONF_ERROR;
    }

    complex->code = ngx_http_script_complex_value_code;
    complex->lengths = NULL;

    ngx_memzero(&sc, sizeof(ngx_http_script_compile_t));

    sc.cf = cf;
    sc.source = value;
    sc.lengths = &complex->lengths;
    sc.values = &lcf->codes;
    sc.variables = n;
    sc.complete_lengths = 1;

    if (ngx_http_script_compile(&sc) != NGX_OK) {
        return NGX_CONF_ERROR;
    }

    return NGX_CONF_OK;
}


char *
ngx_http_lua_set_multi_var(ngx_conf_t *cf, ngx_str_t *name, ngx_str_t *value,
        ngx_http_lua_var_filter_t *filter)
{
    ngx_int_t                            i, index;
    ngx_http_variable_t                 *v;
    ngx_http_script_var_code_t          *vcode;
    ngx_http_lua_rewrite_loc_conf_t     *rlcf;
    ngx_http_script_var_handler_code_t  *vhcode;

    if (name->data[0] != '$') {
        ngx_conf_log_error(NGX_LOG_EMERG, cf, 0,
                           "invalid variable name \"%V\"", name);
        return NGX_CONF_ERROR;
    }

    name->len--;
    name->data++;

    v = ngx_http_add_variable(cf, name, NGX_HTTP_VAR_CHANGEABLE);
    if (v == NULL) {
        return NGX_CONF_ERROR;
    }

    index = ngx_http_get_variable_index(cf, name);
    if (index == NGX_ERROR) {
        return NGX_CONF_ERROR;
    }

    if (v->get_handler == NULL
        && ngx_strncasecmp(name->data, (u_char *) "arg_", 4) != 0
        && ngx_strncasecmp(name->data, (u_char *) "cookie_", 7) != 0
        && ngx_strncasecmp(name->data, (u_char *) "http_", 5) != 0
        && ngx_strncasecmp(name->data, (u_char *) "sent_http_", 10) != 0
        && ngx_strncasecmp(name->data, (u_char *) "upstream_http_", 14) != 0)
    {
        v->get_handler = ngx_http_lua_rewrite_var;
        v->data = index;
    }

    rlcf = ngx_http_conf_get_module_loc_conf(cf, ngx_http_rewrite_module);

    for (i = filter->size; i; i--, value++) {
        if (ngx_http_lua_rewrite_value(cf, rlcf, value)
            != NGX_CONF_OK)
        {
            return NGX_CONF_ERROR;
        }
    }

    if (filter->size > 10) {
        if (rlcf->stack_size == NGX_CONF_UNSET_UINT
            || rlcf->stack_size < filter->size)
        {
            rlcf->stack_size = filter->size;
        }
    }

    if (ngx_http_lua_set_var_filter(cf, rlcf, filter) != NGX_CONF_OK) {
        return NGX_CONF_ERROR;
    }

    if (v->set_handler) {
        vhcode = ngx_http_script_start_code(cf->pool, &rlcf->codes,
                                   sizeof(ngx_http_script_var_handler_code_t));
        if (vhcode == NULL) {
            return NGX_CONF_ERROR;
        }

        vhcode->code = ngx_http_script_var_set_handler_code;
        vhcode->handler = v->set_handler;
        vhcode->data = v->data;

        return NGX_CONF_OK;
    }

    vcode = ngx_http_script_start_code(cf->pool, &rlcf->codes,
                                       sizeof(ngx_http_script_var_code_t));
    if (vcode == NULL) {
        return NGX_CONF_ERROR;
    }

    vcode->code = ngx_http_script_set_var_code;
    vcode->index = (uintptr_t) index;

    return NGX_CONF_OK;
}
#endif
