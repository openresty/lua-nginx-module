#ifndef DDEBUG
#define DDEBUG 0
#endif
#include "ddebug.h"

#if (NGX_PCRE)

#include "ngx_http_lua_regex.h"
#include "ngx_http_lua_script.h"
#include <pcre.h>


static int ngx_http_lua_ngx_re_gmatch_iterator(lua_State *L);
static void ngx_http_lua_ngx_re_parse_opts(lua_State *L,
        ngx_regex_compile_t *re, ngx_str_t *opts, int narg);


int
ngx_http_lua_ngx_re_match(lua_State *L)
{
    ngx_http_request_t          *r;
    ngx_str_t                    subj;
    ngx_str_t                    pat;
    ngx_str_t                    opts;
    ngx_regex_compile_t          re;
    const char                  *msg;
    ngx_int_t                    rc;
    ngx_uint_t                   n;
    int                          i;
    int                          nargs;
    int                         *cap;
    int                          ovecsize;
    u_char                       errstr[NGX_MAX_CONF_ERRSTR + 1];

    nargs = lua_gettop(L);

    if (nargs != 2 && nargs != 3) {
        return luaL_error(L, "expecting two or three arguments, but got %d",
                nargs);
    }

    lua_getglobal(L, GLOBALS_SYMBOL_REQUEST);
    r = lua_touserdata(L, -1);
    lua_pop(L, 1);

    if (r == NULL) {
        return luaL_error(L, "no request object found");
    }

    subj.data = (u_char *) luaL_checklstring(L, 1, &subj.len);
    pat.data = (u_char *) luaL_checklstring(L, 2, &pat.len);

    ngx_memzero(&re, sizeof(ngx_regex_compile_t));

    if (nargs >= 3) {
        opts.data = (u_char *) luaL_checklstring(L, 3, &opts.len);

    } else {
        opts.data = (u_char *) "";
        opts.len = 0;
    }

    re.pattern = pat;
    re.options = 0;
    re.err.len = NGX_MAX_CONF_ERRSTR;
    re.err.data = errstr;
    re.pool = r->pool;

    ngx_http_lua_ngx_re_parse_opts(L, &re, &opts, 3);

    dd("compiling regex");

    if (ngx_regex_compile(&re) != NGX_OK) {
        dd("compile failed");

        re.err.data[re.err.len] = '\0';
        msg = lua_pushfstring(L, "failed to compile regex \"%s\": %s",
                pat.data, re.err.data);

        return luaL_argerror(L, 2, msg);
    }

    dd("compile done, captures %d", re.captures);

    ovecsize = (re.captures + 1) * 3;

    cap = ngx_palloc(r->pool, ovecsize * sizeof(int));
    if (cap == NULL) {
        return luaL_error(L, "out of memory");
    }

    rc = ngx_regex_exec(re.regex, &subj, cap, ovecsize);
    if (rc == NGX_REGEX_NO_MATCHED) {
        ngx_pfree(r->pool, cap);
        lua_pushnil(L);
        return 1;
    }

    if (rc < 0) {
        ngx_pfree(r->pool, cap);
        return luaL_error(L, ngx_regex_exec_n " failed: %d on \"%s\" "
                "using \"%s\"", (int) rc, subj.data, pat.data);
    }

    if (rc == 0) {
        ngx_pfree(r->pool, cap);
        return luaL_error(L, "capture size too small");
    }

    dd("rc = %d", (int) rc);

    lua_createtable(L, re.captures /* narr */, 1 /* nrec */);

    for (i = 0, n = 0; i < rc; i++, n += 2) {
        dd("capture %d: %d %d", i, cap[n], cap[n + 1]);
        if (cap[n] < 0) {
            lua_pushnil(L);

        } else {
            lua_pushlstring(L, (char *) &subj.data[cap[n]],
                    cap[n + 1] - cap[n]);

            dd("pushing capture %s at %d", lua_tostring(L, -1), (int) i);
        }

        lua_rawseti(L, -2, (int) i);
    }

    ngx_pfree(r->pool, cap);

    return 1;
}


int
ngx_http_lua_ngx_re_gmatch(lua_State *L)
{
    ngx_http_request_t          *r;
    ngx_str_t                    pat;
    ngx_str_t                    opts;
    ngx_regex_compile_t         *re;
    const char                  *msg;
    int                          nargs;
    u_char                       errstr[NGX_MAX_CONF_ERRSTR + 1];

    nargs = lua_gettop(L);

    if (nargs != 2 && nargs != 3) {
        return luaL_error(L, "expecting two or three arguments, but got %d",
                nargs);
    }

    lua_getglobal(L, GLOBALS_SYMBOL_REQUEST);
    r = lua_touserdata(L, -1);
    lua_pop(L, 1);

    if (r == NULL) {
        return luaL_error(L, "no request object found");
    }

    pat.data = (u_char *) luaL_checklstring(L, 2, &pat.len);

    re = ngx_pcalloc(r->pool, sizeof(ngx_regex_compile_t));
    if (re == NULL) {
        return luaL_error(L, "out of memory");
    }

    if (nargs == 3) {
        opts.data = (u_char *) luaL_checklstring(L, 3, &opts.len);
        lua_pop(L, 2);

    } else {
        opts.data = (u_char *) "";
        opts.len = 0;
        lua_pop(L, 1);
    }

    /* stack: subj regex */

    re->pattern = pat;
    re->options = 0;
    re->err.len = NGX_MAX_CONF_ERRSTR;
    re->err.data = errstr;
    re->pool = r->pool;

    ngx_http_lua_ngx_re_parse_opts(L, re, &opts, 3);

    dd("compiling regex");

    if (ngx_regex_compile(re) != NGX_OK) {
        dd("compile failed");

        re->err.data[re->err.len] = '\0';
        msg = lua_pushfstring(L, "failed to compile regex \"%s\": %s",
                pat.data, re->err.data);

        return luaL_argerror(L, 2, msg);
    }

    dd("compile done, captures %d", re->captures);

    lua_pushlightuserdata(L, r);
    lua_pushlightuserdata(L, re);
    lua_pushinteger(L, 0); /* push the offset */

    /* upvalues in order: subj r re offset */

    dd("offset %d, re %p, r %p", 0, re, r);

    lua_pushcclosure(L, ngx_http_lua_ngx_re_gmatch_iterator, 4);
    return 1;
}


static int
ngx_http_lua_ngx_re_gmatch_iterator(lua_State *L)
{
    int                          ovecsize;
    ngx_regex_compile_t         *re;
    ngx_http_request_t          *r;
    ngx_http_request_t          *orig_r;
    int                         *cap;
    ngx_int_t                    rc;
    ngx_uint_t                   n;
    int                          i;
    ngx_str_t                    subj;
    int                          offset;

    /* upvalues in order: subj r re offset */

    subj.data = (u_char *) lua_tolstring(L, lua_upvalueindex(1), &subj.len);
    orig_r = (ngx_http_request_t *) lua_touserdata(L, lua_upvalueindex(2));
    re = (ngx_regex_compile_t *) lua_touserdata(L, lua_upvalueindex(3));
    offset = lua_tointeger(L, lua_upvalueindex(4));

    dd("offset %d, re %p, r %p, subj %s", offset, re, orig_r, subj.data);

    if (offset < 0) {
        lua_pushnil(L);
        return 1;
    }

    lua_getglobal(L, GLOBALS_SYMBOL_REQUEST);
    r = lua_touserdata(L, -1);
    lua_pop(L, 1);

    if (r == NULL) {
        return luaL_error(L, "no request object found");
    }

    if (r != orig_r || r->pool != orig_r->pool) {
        return luaL_error(L, "attemp to use ngx.re.gmatch iterator in a "
                "request that did not create it");
    }

    ovecsize = (re->captures + 1) * 3;

    cap = ngx_palloc(r->pool, ovecsize * sizeof(int));
    if (cap == NULL) {
        ngx_pfree(r->pool, re);
        return luaL_error(L, "out of memory");
    }

    subj.data += offset;
    subj.len -= offset;

    dd("regex exec...");

    rc = ngx_regex_exec(re->regex, &subj, cap, ovecsize);
    if (rc == NGX_REGEX_NO_MATCHED) {
        /* set upvalue "offset" to -1 */
        lua_pushinteger(L, -1);
        lua_replace(L, lua_upvalueindex(4));
        ngx_pfree(r->pool, re);

        ngx_pfree(r->pool, cap);
        lua_pushnil(L);
        return 1;
    }

    if (rc < 0) {
        lua_pushinteger(L, -1);
        lua_replace(L, lua_upvalueindex(4));
        ngx_pfree(r->pool, re);

        ngx_pfree(r->pool, cap);

        return luaL_error(L, ngx_regex_exec_n " failed: %d on \"%s\"",
                (int) rc, subj.data);
    }

    if (rc == 0) {
        lua_pushinteger(L, -1);
        lua_replace(L, lua_upvalueindex(4));
        ngx_pfree(r->pool, re);
        ngx_pfree(r->pool, cap);
        return luaL_error(L, "capture size too small");
    }

    dd("rc = %d", (int) rc);

    lua_createtable(L, re->captures /* narr */, 1 /* nrec */);

    for (i = 0, n = 0; i < rc; i++, n += 2) {
        dd("capture %d: %d %d", i, cap[n], cap[n + 1]);
        if (cap[n] < 0) {
            lua_pushnil(L);

        } else {
            lua_pushlstring(L, (char *) &subj.data[cap[n]],
                    cap[n + 1] - cap[n]);

            dd("pushing capture %s at %d", lua_tostring(L, -1), (int) i);
        }

        lua_rawseti(L, -2, (int) i);
    }

    offset += cap[1];
    if (offset == (ssize_t) subj.len) {
        offset = -1;
        ngx_pfree(r->pool, re);
    }

    lua_pushinteger(L, offset);
    lua_replace(L, lua_upvalueindex(4));

    ngx_pfree(r->pool, cap);

    return 1;

}


int
ngx_http_lua_ngx_re_sub(lua_State *L)
{
    ngx_http_request_t          *r;
    ngx_str_t                    subj;
    ngx_str_t                    pat;
    ngx_str_t                    opts;
    ngx_str_t                    tpl;
    ngx_str_t                    repl;
    ngx_regex_compile_t          re;
    u_char                      *p;
    const char                  *msg;
    ngx_int_t                    rc;
    ngx_uint_t                   n;
    ngx_int_t                    i;
    int                          nargs;
    int                         *cap;
    int                          ovecsize;
    int                          type;
    unsigned                     func;
    size_t                       len;
    u_char                       errstr[NGX_MAX_CONF_ERRSTR + 1];

    ngx_http_lua_complex_value_t              ctpl;
    ngx_http_lua_compile_complex_value_t       ccv;

    nargs = lua_gettop(L);

    if (nargs != 3 && nargs != 4) {
        return luaL_error(L, "expecting three or four arguments, but got %d",
                nargs);
    }

    lua_getglobal(L, GLOBALS_SYMBOL_REQUEST);
    r = lua_touserdata(L, -1);
    lua_pop(L, 1);

    if (r == NULL) {
        return luaL_error(L, "no request object found");
    }

    subj.data = (u_char *) luaL_checklstring(L, 1, &subj.len);
    pat.data = (u_char *) luaL_checklstring(L, 2, &pat.len);

    func = 0;

    type = lua_type(L, 3);
    switch (type) {
        case LUA_TFUNCTION:
            func = 1;
            break;

        case LUA_TNUMBER:
        case LUA_TSTRING:
            tpl.data = (u_char *) lua_tolstring(L, 3, &tpl.len);
            break;

        default:
            msg = lua_pushfstring(L, "string, number, or function expected, "
                    "got %s", lua_typename(L, type));
            return luaL_argerror(L, 3, msg);
    }

    ngx_memzero(&re, sizeof(ngx_regex_compile_t));

    if (nargs == 4) {
        opts.data = (u_char *) luaL_checklstring(L, 4, &opts.len);
        lua_pop(L, 1);

    } else { /* nargs == 3 */
        opts.data = (u_char *) "";
        opts.len = 0;
    }

    re.pattern = pat;
    re.options = 0;
    re.err.len = NGX_MAX_CONF_ERRSTR;
    re.err.data = errstr;
    re.pool = r->pool;

    ngx_http_lua_ngx_re_parse_opts(L, &re, &opts, 4);

    dd("compiling regex");

    if (ngx_regex_compile(&re) != NGX_OK) {
        dd("compile failed");

        re.err.data[re.err.len] = '\0';
        msg = lua_pushfstring(L, "failed to compile regex \"%s\": %s",
                pat.data, re.err.data);

        return luaL_argerror(L, 2, msg);
    }

    dd("compile done, captures %d", re.captures);

    ovecsize = (re.captures + 1) * 3;

    cap = ngx_palloc(r->pool, ovecsize * sizeof(int));
    if (cap == NULL) {
        return luaL_error(L, "out of memory");
    }

    rc = ngx_regex_exec(re.regex, &subj, cap, ovecsize);
    if (rc == NGX_REGEX_NO_MATCHED) {
        ngx_pfree(r->pool, cap);

        lua_settop(L, 1);
        lua_pushinteger(L, 0);
        return 2;
    }

    if (rc < 0) {
        ngx_pfree(r->pool, cap);
        return luaL_error(L, ngx_regex_exec_n " failed: %d on \"%s\" "
                "using \"%s\"", (int) rc, subj.data, pat.data);
    }

    if (rc == 0) {
        ngx_pfree(r->pool, cap);
        return luaL_error(L, "capture size too small");
    }

    dd("rc = %d", (int) rc);

    if (func) {
        lua_createtable(L, re.captures /* narr */, 1 /* nrec */);

        for (i = 0, n = 0; i < rc; i++, n += 2) {
            dd("capture %d: %d %d", (int) i, cap[n], cap[n + 1]);
            if (cap[n] < 0) {
                lua_pushnil(L);

            } else {
                lua_pushlstring(L, (char *) &subj.data[cap[n]],
                        cap[n + 1] - cap[n]);

                dd("pushing capture %s at %d", lua_tostring(L, -1), (int) i);
            }

            lua_rawseti(L, -2, (int) i);
        }

        lua_call(L, 1 /* nargs */, 1 /* nresults */);
        type = lua_type(L, -1);
        switch (type) {
            case LUA_TNUMBER:
            case LUA_TSTRING:
                tpl.data = (u_char *) lua_tolstring(L, -1, &tpl.len);
                break;

            default:
                msg = lua_pushfstring(L, "string or number expected to be "
                        "returned by the replace function, got %s",
                        lua_typename(L, type));
                return luaL_argerror(L, 3, msg);
        }

        len = cap[0] + tpl.len + subj.len - cap[1];
        repl.len = len;
        repl.data = ngx_palloc(r->pool, len);
        if (repl.data == NULL) {
            return luaL_error(L, "out of memory");
        }

        dd("len = %d", (int) len);
        dd("tpl = %s", tpl.data);

        p = ngx_copy(repl.data, subj.data, cap[0]);
        p = ngx_copy(p, tpl.data, tpl.len);
        p = ngx_copy(p, &subj.data[cap[1]], subj.len - cap[1]);

        lua_pushlstring(L, (char *) repl.data, repl.len);

        ngx_pfree(r->pool, repl.data);
        ngx_pfree(r->pool, cap);

        lua_pushinteger(L, 1);

        return 2;
    }

    ngx_memzero(&ccv, sizeof(ngx_http_lua_compile_complex_value_t));
    ccv.request = r;
    ccv.value = &tpl;
    ccv.complex_value = &ctpl;

    if (ngx_http_lua_compile_complex_value(&ccv) != NGX_OK) {
        ngx_pfree(r->pool, cap);
        return luaL_error(L, "bad template for substitution: \"%s\"", tpl.data);
    }

    rc = ngx_http_lua_complex_value(r, &subj, rc, cap, &ctpl, &repl);

    ngx_pfree(r->pool, cap);

    if (rc != NGX_OK) {
        return luaL_error(L, "failed to eval the template for replacement: "
                "\"%s\"", tpl.data);
    }

    lua_pushlstring(L, (char *) repl.data, repl.len);
    ngx_pfree(r->pool, repl.data);

    lua_pushinteger(L, 1);

    return 2;
}


static void
ngx_http_lua_ngx_re_parse_opts(lua_State *L, ngx_regex_compile_t *re,
        ngx_str_t *opts, int narg)
{
    u_char          *p;
    const char      *msg;

    p = opts->data;

    while (*p != '\0') {
        switch (*p) {
            case 'i':
                re->options |= NGX_REGEX_CASELESS;
                break;

            case 's':
                re->options |= PCRE_DOTALL;
                break;

            case 'm':
                re->options |= PCRE_MULTILINE;
                break;

            case 'u':
                re->options |= PCRE_UTF8;
                break;

            case 'x':
                re->options |= PCRE_EXTENDED;
                break;

            case 'a':
                re->options |= PCRE_ANCHORED;
                break;

            default:
                msg = lua_pushfstring(L, "unknown flag \"%c\"", *p);
                luaL_argerror(L, narg, msg);
        }

        p++;
    }
}


#endif /* NGX_PCRE */

