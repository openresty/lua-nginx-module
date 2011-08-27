#ifndef DDEBUG
#define DDEBUG 0
#endif
#include "ddebug.h"

#if (NGX_PCRE)

#include "ngx_http_lua_regex.h"
#include "ngx_http_lua_script.h"
#include "ngx_http_lua_patch.h"
#include <pcre.h>


static int ngx_http_lua_ngx_re_gmatch_iterator(lua_State *L);
static unsigned ngx_http_lua_ngx_re_parse_opts(lua_State *L,
        ngx_regex_compile_t *re, ngx_str_t *opts, int narg);
static int ngx_http_lua_ngx_re_sub_helper(lua_State *L, unsigned global);


#define ngx_http_lua_regex_exec(re, s, start, captures, size) \
    pcre_exec(re, NULL, (const char *) (s)->data, (s)->len, start, 0, \
              captures, size)


int
ngx_http_lua_ngx_re_match(lua_State *L)
{
    /* u_char                      *p; */
    ngx_http_request_t          *r;
    ngx_str_t                    subj;
    ngx_str_t                    pat;
    ngx_str_t                    opts;
    ngx_regex_compile_t          re_comp;
    ngx_http_lua_regex_t        *re;
    const char                  *msg;
    ngx_int_t                    rc;
    ngx_uint_t                   n;
    int                          i;
    ngx_int_t                    pos = 0;
    int                          nargs;
    int                         *cap;
    int                          ovecsize;
    unsigned                     comp_once;
    ngx_pool_t                  *pool;
    ngx_http_lua_main_conf_t    *lmcf;
    u_char                       errstr[NGX_MAX_CONF_ERRSTR + 1];

    nargs = lua_gettop(L);

    if (nargs != 2 && nargs != 3 && nargs != 4) {
        return luaL_error(L, "expecting two or three or four arguments, "
                "but got %d", nargs);
    }

    lua_getglobal(L, GLOBALS_SYMBOL_REQUEST);
    r = lua_touserdata(L, -1);
    lua_pop(L, 1);

    if (r == NULL) {
        return luaL_error(L, "no request object found");
    }

    subj.data = (u_char *) luaL_checklstring(L, 1, &subj.len);
    pat.data = (u_char *) luaL_checklstring(L, 2, &pat.len);

    ngx_memzero(&re_comp, sizeof(ngx_regex_compile_t));

    if (nargs >= 3) {
        opts.data = (u_char *) luaL_checklstring(L, 3, &opts.len);

        if (nargs == 4) {
            luaL_checktype(L, 4, LUA_TTABLE);
            lua_getfield(L, 4, "pos");
            if (lua_isnumber(L, -1)) {
                pos = (ngx_int_t) lua_tointeger(L, -1);
                if (pos < 0) {
                    pos = 0;
                }

            } else if (lua_isnil(L, -1)) {
                pos = 0;

            } else {
                msg = lua_pushfstring(L, "bad pos field type in the ctx table "
                        "argument: %s",
                        luaL_typename(L, -1));

                return luaL_argerror(L, 4, msg);
            }

            lua_pop(L, 1);
        }

    } else {
        opts.data = (u_char *) "";
        opts.len = 0;
    }

    re_comp.options = 0;

    comp_once = ngx_http_lua_ngx_re_parse_opts(L, &re_comp, &opts, 3);

    if (comp_once) {
        lmcf = ngx_http_get_module_main_conf(r, ngx_http_lua_module);
        pool = lmcf->pool;

        dd("server pool %p", lmcf->pool);

        lua_getfield(L, LUA_REGISTRYINDEX, NGX_LUA_REGEX_CACHE); /* table */

        lua_pushvalue(L, 2); /* table regex */

        dd("options size: %d", (int) sizeof(re_comp.options));

        lua_pushlstring(L, (char *) &re_comp.options, sizeof(re_comp.options));
                /* table regex opts */

        lua_concat(L, 2); /* table key */
        lua_pushvalue(L, -1); /* table key key */

        dd("regex cache key: %.*s", (int) (pat.len + sizeof(re_comp.options)),
                lua_tostring(L, -1));

        lua_rawget(L, -3); /* table key re */
        re = lua_touserdata(L, -1);

        lua_pop(L, 1); /* table key */

        if (re) {
            ngx_log_debug2(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                    "lua regex cache hit for regex \"%s\" with options \"%s\"",
                    pat.data, opts.data);

            lua_pop(L, 2);

            dd("restoring regex %p, ncaptures %d,  captures %p", re->regex,
                    re->ncaptures, re->captures);

            re_comp.regex = re->regex;
            re_comp.captures = re->ncaptures;
            cap = re->captures;

            ovecsize = (re->ncaptures + 1) * 3;

            goto exec;
        }

        ngx_log_debug2(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                "lua regex cache miss for regex \"%s\" with options \"%s\"",
                pat.data, opts.data);

        if (lmcf->regex_cache_entries >= lmcf->regex_cache_max_entries) {

            if (lmcf->regex_cache_entries == lmcf->regex_cache_max_entries) {
                ngx_log_error(NGX_LOG_WARN, r->connection->log, 0,
                        "lua exceeding regex cache max entries (%i)",
                        lmcf->regex_cache_max_entries);

                lmcf->regex_cache_entries++;
            }

            pool = r->pool;
            comp_once = 0;
        }

    } else {
        pool = r->pool;
    }

    dd("pool %p, r pool %p", pool, r->pool);

    re_comp.pool = pool;
    re_comp.pattern = pat;
    re_comp.err.len = NGX_MAX_CONF_ERRSTR;
    re_comp.err.data = errstr;

    ngx_log_debug3(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
            "lua compiling pcre regex \"%s\" with options \"%s\" "
            "(compile once: %d)", subj.data, opts.data, comp_once);

    ngx_http_lua_pcre_malloc_done();

    rc = ngx_regex_compile(&re_comp);

    ngx_http_lua_pcre_malloc_init(r->pool);

    if (rc != NGX_OK) {
        dd("compile failed");

        re_comp.err.data[re_comp.err.len] = '\0';
        msg = lua_pushfstring(L, "failed to compile regex \"%s\": %s",
                pat.data, re_comp.err.data);

        return luaL_argerror(L, 2, msg);
    }

    dd("compile done, captures %d", (int) re_comp.captures);

    ovecsize = (re_comp.captures + 1) * 3;

    dd("allocating cap with size: %d", (int) ovecsize);
    cap = ngx_palloc(pool, ovecsize * sizeof(int));
    if (cap == NULL) {
        return luaL_error(L, "out of memory");
    }

    if (comp_once) {

        ngx_log_debug1(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                "lua saving compiled regex (%d captures) into the cache "
                "(entries %i)", re_comp.captures, lmcf->regex_cache_entries);

        re = ngx_palloc(pool, sizeof(ngx_http_lua_regex_t));
        if (re == NULL) {
            return luaL_error(L, "out of memory");
        }

        dd("saving regex %p, ncaptures %d,  captures %p", re_comp.regex,
                re_comp.captures, cap);

        re->regex = re_comp.regex;
        re->ncaptures = re_comp.captures;
        re->captures = cap;
        lua_pushlightuserdata(L, re); /* table key value */
        lua_rawset(L, -3); /* table */
        lua_pop(L, 1);

        lmcf->regex_cache_entries++;
    }

exec:
    rc = ngx_http_lua_regex_exec(re_comp.regex, &subj, (int) pos, cap,
            ovecsize);

    if (rc == NGX_REGEX_NO_MATCHED) {
        ngx_log_debug3(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                "regex \"%s\" not matched on string \"%s\" starting from %z",
                pat.data, subj.data, pos);

        if (!comp_once) {
            ngx_pfree(pool, cap);
        }

        lua_pushnil(L);
        return 1;
    }

    if (rc < 0) {
        if (!comp_once) {
            ngx_pfree(pool, cap);
        }
        return luaL_error(L, ngx_regex_exec_n " failed: %d on \"%s\" "
                "using \"%s\"", (int) rc, subj.data, pat.data);
    }

    if (rc == 0) {
        if (!comp_once) {
            ngx_pfree(pool, cap);
        }
        return luaL_error(L, "capture size too small");
    }

    dd("rc = %d", (int) rc);

    lua_createtable(L, re_comp.captures /* narr */, 1 /* nrec */);

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

    if (nargs == 4) { /* having ctx table */
        pos = cap[1];
        lua_pushinteger(L, (lua_Integer) pos);
        lua_setfield(L, 4, "pos");
    }

    if (!comp_once) {
        ngx_pfree(pool, cap);
    }

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
    ngx_int_t                    offset;

    /* upvalues in order: subj r re offset */

    subj.data = (u_char *) lua_tolstring(L, lua_upvalueindex(1), &subj.len);
    orig_r = (ngx_http_request_t *) lua_touserdata(L, lua_upvalueindex(2));
    re = (ngx_regex_compile_t *) lua_touserdata(L, lua_upvalueindex(3));
    offset = (ngx_int_t) lua_tointeger(L, lua_upvalueindex(4));

    dd("offset %d, re %p, r %p, subj %s", (int) offset, re, orig_r, subj.data);

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

    dd("regex exec...");

    rc = ngx_http_lua_regex_exec(re->regex, &subj, offset, cap, ovecsize);
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

    offset = cap[1];
    if (offset == (ssize_t) subj.len) {
        offset = -1;
        ngx_pfree(r->pool, re);
    }

    lua_pushinteger(L, (lua_Integer) offset);
    lua_replace(L, lua_upvalueindex(4));

    ngx_pfree(r->pool, cap);

    return 1;
}


static unsigned
ngx_http_lua_ngx_re_parse_opts(lua_State *L, ngx_regex_compile_t *re,
        ngx_str_t *opts, int narg)
{
    u_char          *p;
    const char      *msg;
    unsigned         compile_once = 0;

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

            case 'o':
                compile_once = 1;
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

    return compile_once;
}


int
ngx_http_lua_ngx_re_sub(lua_State *L)
{
    return ngx_http_lua_ngx_re_sub_helper(L, 0 /* global */);
}


int
ngx_http_lua_ngx_re_gsub(lua_State *L)
{
    return ngx_http_lua_ngx_re_sub_helper(L, 1 /* global */);
}


static int
ngx_http_lua_ngx_re_sub_helper(lua_State *L, unsigned global)
{
    ngx_http_request_t          *r;
    ngx_str_t                    subj;
    ngx_str_t                    pat;
    ngx_str_t                    opts;
    ngx_str_t                    tpl;
    ngx_regex_compile_t          re;
    const char                  *msg;
    ngx_int_t                    rc;
    ngx_uint_t                   n;
    ngx_int_t                    i;
    int                          nargs;
    int                         *cap;
    int                          ovecsize;
    int                          type;
    unsigned                     func;
    size_t                       offset;
    size_t                       count;
    luaL_Buffer                  luabuf;
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

    count = 0;
    offset = 0;

    for (;;) {
        if (subj.len == 0) {
            break;
        }

        rc = ngx_http_lua_regex_exec(re.regex, &subj, offset, cap, ovecsize);
        if (rc == NGX_REGEX_NO_MATCHED) {
            break;
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

        count++;

        if (count == 1) {
            luaL_buffinit(L, &luabuf);
        }

        if (func) {
            lua_pushvalue(L, -1);

            lua_createtable(L, re.captures /* narr */, 1 /* nrec */);

            for (i = 0, n = 0; i < rc; i++, n += 2) {
                dd("capture %d: %d %d", (int) i, cap[n], cap[n + 1]);
                if (cap[n] < 0) {
                    lua_pushnil(L);

                } else {
                    lua_pushlstring(L, (char *) &subj.data[cap[n]],
                            cap[n + 1] - cap[n]);

                    dd("pushing capture %s at %d", lua_tostring(L, -1),
                            (int) i);
                }

                lua_rawseti(L, -2, (int) i);
            }

            dd("stack size at call: %d", lua_gettop(L));

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

            luaL_addlstring(&luabuf, (char *) &subj.data[offset],
                    cap[0] - offset);

            luaL_addlstring(&luabuf, (char *) tpl.data, tpl.len);

            lua_pop(L, 1);

            offset = cap[1];

            if (global) {
                continue;
            }

            break;
        }

        if (count == 1) {
            ngx_memzero(&ccv, sizeof(ngx_http_lua_compile_complex_value_t));
            ccv.request = r;
            ccv.value = &tpl;
            ccv.complex_value = &ctpl;

            if (ngx_http_lua_compile_complex_value(&ccv) != NGX_OK) {
                ngx_pfree(r->pool, cap);
                return luaL_error(L, "bad template for substitution: \"%s\"",
                        tpl.data);
            }
        }

        rc = ngx_http_lua_complex_value(r, &subj, offset, rc, cap, &ctpl,
                &luabuf);

        if (rc != NGX_OK) {
            ngx_pfree(r->pool, cap);
            return luaL_error(L, "failed to eval the template for replacement: "
                    "\"%s\"", tpl.data);
        }

        offset = cap[1];

        if (global) {
            continue;
        }

        break;
    }

    if (count == 0) {
        dd("no match, just the original subject");
        lua_settop(L, 1);

    } else {
        if (offset != subj.len) {
            dd("adding trailer: %s (len %d)", &subj.data[offset],
                    (int) (subj.len - offset));

            luaL_addlstring(&luabuf, (char *) &subj.data[offset],
                    subj.len - offset);
        }

        luaL_pushresult(&luabuf);

        dd("the dst string: %s", lua_tostring(L, -1));
    }

    ngx_pfree(r->pool, cap);

    lua_pushinteger(L, count);
    return 2;
}

#endif /* NGX_PCRE */

