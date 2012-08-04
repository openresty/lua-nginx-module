#include "ngx_http_lua_socket_log.h"

void ngx_http_lua_socket_log_error(ngx_uint_t level, ngx_http_request_t *r,
                                   ngx_err_t err, const char *fmt, ...)
{
    ngx_http_lua_loc_conf_t *llcf;
    ngx_log_t *log;
    va_list  args;

    llcf = ngx_http_get_module_loc_conf(r, ngx_http_lua_module);

    if (llcf->log_socket_errors) {
        log = r->connection->log;
        if (log->log_level >= level) {
            va_start(args, fmt);
            ngx_log_error_core(level, log, err, fmt, args);
            va_end(args);
        }
    }
}
