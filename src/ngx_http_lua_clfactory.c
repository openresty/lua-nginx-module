/* vim:set ft=c ts=4 sw=4 et fdm=marker: */
#include "ngx_http_lua_clfactory.h"

typedef struct {
    int sent_begin;
    int sent_end;
    int extraline;
    FILE *f;
    char buff[LUAL_BUFFERSIZE];
} clfactory_file_ctx_t;

typedef struct {
    int sent_begin;
    int sent_end;
    const char *s;
    size_t size;
} clfactory_buffer_ctx_t;

static const char* clfactory_getF(lua_State *l, void *ud, size_t *size);
static int clfactory_errfile(lua_State *l, const char *what, int fnameindex);
static const char* clfactory_getS(lua_State *l, void *ud, size_t *size);

int
ngx_http_lua_clfactory_loadfile(lua_State *l, const char *filename)
{
    clfactory_file_ctx_t lf;
    int status, readstatus;
    int c;
    int fnameindex = lua_gettop(l) + 1;  /* index of filename on the stack */

    lf.extraline = 0;

    if (filename == NULL) {
        lua_pushliteral(l, "=stdin");
        lf.f = stdin;
    } else {
        lua_pushfstring(l, "@%s", filename);
        lf.f = fopen(filename, "r");
        if (lf.f == NULL)
            return clfactory_errfile(l, "open", fnameindex);
    }

    c = getc(lf.f);
    if (c == '#') {  /* Unix exec. file? */
        lf.extraline = 1;
        while ((c = getc(lf.f)) != EOF && c != '\n') ;  /* skip first line */
        if (c == '\n')
            c = getc(lf.f);
    }

    if (c == LUA_SIGNATURE[0] && filename) {  /* binary file? */
        /* no binary file supported as closure factory code needs to be */
        /* compiled to bytecode along with user code */
        return clfactory_errfile(l, "load binary file", fnameindex);
    }

    ungetc(c, lf.f);

    lf.sent_begin = lf.sent_end = 0;
    status = lua_load(l, clfactory_getF, &lf, lua_tostring(l, -1));

    readstatus = ferror(lf.f);
    if (filename)
        fclose(lf.f);  /* close file (even in case of errors) */

    if (readstatus) {
        lua_settop(l, fnameindex);  /* ignore results from `lua_load' */
        return clfactory_errfile(l, "read", fnameindex);
    }

    lua_remove(l, fnameindex);
    return status;
}

int ngx_http_lua_clfactory_loadstring(lua_State *l, const char *s)
{
    return ngx_http_lua_clfactory_loadbuffer(l, s, strlen(s), s);
}

int ngx_http_lua_clfactory_loadbuffer(lua_State *l, const char *buff, size_t size, const char *name)
{
    clfactory_buffer_ctx_t ls;
    ls.s = buff;
    ls.size = size;
    ls.sent_begin = ls.sent_end = 0;
    return lua_load(l, clfactory_getS, &ls, name);
}

static const char*
clfactory_getF(lua_State *l, void *ud, size_t *size)
{
    clfactory_file_ctx_t *lf = (clfactory_file_ctx_t *)ud;
    (void)l;
    if (lf->sent_begin == 0) {
        lf->sent_begin = 1;
        *size = CLFACTORY_BEGIN_SIZE;
        return CLFACTORY_BEGIN_CODE;
    }

    if (lf->extraline) {
        lf->extraline = 0;
        *size = 1;
        return "\n";
    }
    if (feof(lf->f)) {
        if (lf->sent_end == 0) {
            lf->sent_end = 1;
            *size = CLFACTORY_END_SIZE;
            return CLFACTORY_END_CODE;
        }

        return NULL;
    }
    *size = fread(lf->buff, 1, sizeof(lf->buff), lf->f);
    return (*size > 0) ? lf->buff : NULL;
}

static int
clfactory_errfile(lua_State *l, const char *what, int fnameindex)
{
    const char *serr = strerror(errno);
    const char *filename = lua_tostring(l, fnameindex) + 1;
    lua_pushfstring(l, "cannot %s %s: %s", what, filename, serr);
    lua_remove(l, fnameindex);
    return LUA_ERRFILE;
}

static const char*
clfactory_getS(lua_State *l, void *ud, size_t *size)
{
    clfactory_buffer_ctx_t *ls = (clfactory_buffer_ctx_t *)ud;
    (void)l;
    if (ls->sent_begin == 0) {
        ls->sent_begin = 1;
        *size = CLFACTORY_BEGIN_SIZE;
        return CLFACTORY_BEGIN_CODE;
    }
    if (ls->size == 0) {
        if (ls->sent_end == 0) {
            ls->sent_end = 1;
            *size = CLFACTORY_END_SIZE;
            return CLFACTORY_END_CODE;
        }

        return NULL;
    }
    *size = ls->size;
    ls->size = 0;
    return ls->s;
}

