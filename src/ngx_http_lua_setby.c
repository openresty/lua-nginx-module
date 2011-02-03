/* vim:set ft=c ts=4 sw=4 et fdm=marker: */
#define DDEBUG 0
#include "ngx_http_lua_setby.h"
#include "ngx_http_lua_hook.h"
#include "ngx_http_lua_util.h"


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
        lua_pushlstring(L, (const char*)(v[idx].data), v[idx].len);
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
    /*  set NginX request pointer to current lua thread's globals table */
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

    /*  override 'print' function */
    lua_pushcfunction(L, ngx_http_lua_print);
    lua_setfield(L, -2, "print");

    /*  {{{ initialize ngx.* namespace */
    lua_newtable(L);    /*  ngx.* */

    lua_newtable(L);    /*  .arg table aka {} */

    lua_newtable(L);    /*  the metatable for new param table */
    lua_pushinteger(L, nargs);    /*  1st upvalue: argument number */
    lua_pushlightuserdata(L, args);    /*  2nd upvalue: pointer to arguments */

    lua_pushcclosure(L, ngx_http_lua_param_get, 2);
        /*  binding upvalues to __index meta-method closure */

    lua_setfield(L, -2, "__index");
    lua_setmetatable(L, -2);    /*  tie the metatable to param table */

    lua_setfield(L, -2, "arg");    /*  set ngx.arg table */

    /* {{{ register reference maps */
    lua_newtable(L);    /* ngx.var */

    lua_newtable(L); /* metatable for ngx.var */
    lua_pushcfunction(L, ngx_http_lua_var_get);
    lua_setfield(L, -2, "__index");
    lua_pushcfunction(L, ngx_http_lua_var_set);
    lua_setfield(L, -2, "__newindex");
    lua_setmetatable(L, -2);

    lua_setfield(L, -2, "var");
    /*  }}} */

    lua_pushcfunction(L, ngx_http_lua_ngx_escape_uri);
    lua_setfield(L, -2, "escape_uri");

    lua_pushcfunction(L, ngx_http_lua_ngx_unescape_uri);
    lua_setfield(L, -2, "unescape_uri");

    lua_pushcfunction(L, ngx_http_lua_ngx_quote_sql_str);
    lua_setfield(L, -2, "quote_sql_str");

    lua_pushcfunction(L, ngx_http_lua_ngx_decode_base64);
    lua_setfield(L, -2, "decode_base64");

    lua_pushcfunction(L, ngx_http_lua_ngx_encode_base64);
    lua_setfield(L, -2, "encode_base64");

    lua_pushcfunction(L, ngx_http_lua_ngx_md5_bin);
    lua_setfield(L, -2, "md5_bin");

    lua_pushcfunction(L, ngx_http_lua_ngx_md5);
    lua_setfield(L, -2, "md5");

    lua_pushcfunction(L, ngx_http_lua_ngx_time);
    lua_setfield(L, -2, "get_now_ts"); /* deprecated */

    lua_pushcfunction(L, ngx_http_lua_ngx_utctime);
    lua_setfield(L, -2, "utctime");

    lua_pushcfunction(L, ngx_http_lua_ngx_localtime);
    lua_setfield(L, -2, "get_now"); /* deprecated */

    lua_pushcfunction(L, ngx_http_lua_ngx_time);
    lua_setfield(L, -2, "time");

    lua_pushcfunction(L, ngx_http_lua_ngx_localtime);
    lua_setfield(L, -2, "localtime");

    lua_pushcfunction(L, ngx_http_lua_ngx_today);
    lua_setfield(L, -2, "get_today"); /* deprecated */

    lua_pushcfunction(L, ngx_http_lua_ngx_today);
    lua_setfield(L, -2, "today");

    lua_pushcfunction(L, ngx_http_lua_ngx_cookie_time);
    lua_setfield(L, -2, "cookie_time");

    lua_pushcfunction(L, ngx_http_lua_ngx_log);
    lua_setfield(L, -2, "log");

    ngx_http_lua_inject_log_consts(L);

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


ngx_int_t
ngx_http_lua_set_by_chunk(lua_State *L, ngx_http_request_t *r, ngx_str_t *val,
        ngx_http_variable_value_t *args, size_t nargs)
{
    size_t i;
    ngx_int_t rc;

    /*  set Lua VM panic handler */
    lua_atpanic(L, ngx_http_lua_atpanic);

    /*  initialize nginx context in Lua VM, code chunk at stack top    sp = 1 */
    ngx_http_lua_set_by_lua_env(L, r, nargs, args);

    /*  passing directive arguments to the user code */
    for (i = 0; i < nargs; i++) {
        lua_pushlstring(L, (const char*)args[i].data, args[i].len);
    }

    /*  protected call user code */
    rc = lua_pcall(L, nargs, 1, 0);
    if (rc) {
        /*  error occured when running loaded code */
        const char *err_msg = lua_tostring(L, -1);
        ngx_log_error(NGX_LOG_ERR, r->connection->log, 0, "(lua-error) %s",
                err_msg);

        lua_settop(L, 0);    /*  clear remaining elems on stack */
        assert(lua_gettop(L) == 0);

        return NGX_ERROR;
    }

    NGX_LUA_EXCEPTION_TRY {
        size_t rlen;
        const char *rdata = lua_tolstring(L, -1, &rlen);

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
        dd("NginX execution restored");
    }

    /*  clear Lua stack */
    lua_settop(L, 0);

    return NGX_OK;
}

