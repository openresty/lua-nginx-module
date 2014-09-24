-- Copyright (C) 2014 Yichun Zhang


local ffi = require "ffi"
local base = require "resty.core.base"


local C = ffi.C
local ffi_str = ffi.string
local getfenv = getfenv
local errmsg = base.get_errmsg_ptr()
local get_string_buf = base.get_string_buf
local get_size_ptr = base.get_size_ptr
local FFI_DECLINED = base.FFI_DECLINED
local FFI_OK = base.FFI_OK


ffi.cdef[[

struct ngx_ssl_conn_s;
typedef struct ngx_ssl_conn_s  ngx_ssl_conn_t;

int ngx_http_lua_ffi_ssl_set_der_certificate(ngx_http_request_t *r,
    const char *data, size_t len, char **err);

int ngx_http_lua_ffi_ssl_clear_certs(ngx_http_request_t *r, char **err);

int ngx_http_lua_ffi_ssl_set_der_private_key(ngx_http_request_t *r,
    const char *data, size_t len, char **err);

int ngx_http_lua_ffi_ssl_raw_server_addr(ngx_http_request_t *r, char **addr,
    size_t *addrlen, int *addrtype, char **err);

int ngx_http_lua_ffi_ssl_server_name(ngx_http_request_t *r, char **name,
    size_t *namelen, char **err);

]]


local _M = {}


local charpp = ffi.new("char*[1]")
local intp = ffi.new("int[1]")


function _M.clear_certs(data)
    local r = getfenv(0).__ngx_req
    if not r then
        return error("no request found")
    end

    local rc = C.ngx_http_lua_ffi_ssl_clear_certs(r, errmsg)
    if rc == FFI_OK then
        return true
    end

    return nil, ffi_str(errmsg[0])
end


function _M.set_der_cert(data)
    local r = getfenv(0).__ngx_req
    if not r then
        return error("no request found")
    end

    local rc = C.ngx_http_lua_ffi_ssl_set_der_certificate(r, data, #data, errmsg)
    if rc == FFI_OK then
        return true
    end

    return nil, ffi_str(errmsg[0])
end


function _M.set_der_pkey(data)
    local r = getfenv(0).__ngx_req
    if not r then
        return error("no request found")
    end

    local rc = C.ngx_http_lua_ffi_ssl_set_der_private_key(r, data, #data, errmsg)
    if rc == FFI_OK then
        return true
    end

    return nil, ffi_str(errmsg[0])
end


local addr_types = {
    [1] = "unix",
    [2] = "inet",
    [10] = "inet6",
}


function _M.raw_server_addr()
    local r = getfenv(0).__ngx_req
    if not r then
        return error("no request found")
    end

    local sizep = get_size_ptr()

    local rc = C.ngx_http_lua_ffi_ssl_raw_server_addr(r, charpp, sizep,
                                                      intp, errmsg)
    if rc == FFI_OK then
        local typ = addr_types[intp[0]]
        if not typ then
            return nil, nil, "unknown address type: " .. intp[0]
        end
        return ffi_str(charpp[0], sizep[0]), typ
    end

    return nil, nil, ffi_str(errmsg[0])
end


function _M.server_name()
    local r = getfenv(0).__ngx_req
    if not r then
        return error("no request found")
    end

    local sizep = get_size_ptr()

    local rc = C.ngx_http_lua_ffi_ssl_server_name(r, charpp, sizep, errmsg)
    if rc == FFI_OK then
        return ffi_str(charpp[0], sizep[0])
    end

    if rc == FFI_DECLINED then
        return nil
    end

    return nil, ffi_str(errmsg[0])
end


return _M
