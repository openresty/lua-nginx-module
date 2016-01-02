-- Copyright (C) Yichun Zhang (agentzh)


local ffi = require "ffi"
local base = require "resty.core.base"


local C = ffi.C
local ffi_str = ffi.string
local getfenv = getfenv
local errmsg = base.get_errmsg_ptr()
local get_string_buf = base.get_string_buf
local get_string_buf_size = base.get_string_buf_size
local get_size_ptr = base.get_size_ptr
local FFI_DECLINED = base.FFI_DECLINED
local FFI_OK = base.FFI_OK
local FFI_BUSY = base.FFI_BUSY


ffi.cdef[[
int ngx_http_lua_ffi_ssl_get_ocsp_responder_from_der_chain(
    const char *chain_data, size_t chain_len, char *out, size_t *out_size,
    char **err);

int ngx_http_lua_ffi_ssl_create_ocsp_request(const char *chain_data,
    size_t chain_len, unsigned char *out, size_t *out_size, char **err);

int ngx_http_lua_ffi_ssl_validate_ocsp_response(const unsigned char *resp,
    size_t resp_len, const char *chain_data, size_t chain_len,
    unsigned char *errbuf, size_t *errbuf_size);

int ngx_http_lua_ffi_ssl_set_ocsp_status_resp(ngx_http_request_t *r,
    const unsigned char *resp, size_t resp_len, char **err);
]]


local _M = { version = base.version }


function _M.get_ocsp_responder_from_der_chain(data, maxlen)

    local buf_size = maxlen
    if not buf_size then
        buf_size = get_string_buf_size()
    end
    local buf = get_string_buf(buf_size)

    local sizep = get_size_ptr()
    sizep[0] = buf_size

    local rc = C.ngx_http_lua_ffi_ssl_get_ocsp_responder_from_der_chain(data,
                                                    #data, buf, sizep, errmsg)

    if rc == FFI_DECLINED then
        return nil
    end

    if rc == FFI_OK then
        return ffi_str(buf, sizep[0])
    end

    if rc == FFI_BUSY then
        return ffi_str(buf, sizep[0]), "truncated"
    end

    return nil, ffi_str(errmsg[0])
end


function _M.create_ocsp_request(data, maxlen)

    local buf_size = maxlen
    if not buf_size then
        buf_size = get_string_buf_size()
    end
    local buf = get_string_buf(buf_size)

    local sizep = get_size_ptr()
    sizep[0] = buf_size

    local rc = C.ngx_http_lua_ffi_ssl_create_ocsp_request(data,
                                                          #data, buf, sizep,
                                                          errmsg)

    if rc == FFI_OK then
        return ffi_str(buf, sizep[0])
    end

    if rc == FFI_BUSY then
        return nil, ffi_str(errmsg[0]) .. ": " .. tonumber(sizep[0])
               .. " > " .. buf_size
    end

    return nil, ffi_str(errmsg[0])
end


function _M.validate_ocsp_response(resp, chain, max_errmsg_len)

    local errbuf_size = max_errmsg_len
    if not errbuf_size then
        errbuf_size = get_string_buf_size()
    end
    local errbuf = get_string_buf(errbuf_size)

    local sizep = get_size_ptr()
    sizep[0] = errbuf_size

    local rc = C.ngx_http_lua_ffi_ssl_validate_ocsp_response(
                        resp, #resp, chain, #chain, errbuf, sizep)

    if rc == FFI_OK then
        return true
    end

    -- rc == FFI_ERROR

    return nil, ffi_str(errbuf, sizep[0])
end


function _M.set_ocsp_status_resp(data)
    local r = getfenv(0).__ngx_req
    if not r then
        return error("no request found")
    end

    local rc = C.ngx_http_lua_ffi_ssl_set_ocsp_status_resp(r, data, #data,
                                                           errmsg)

    if rc == FFI_DECLINED then
        -- no client status req
        return true, "no status req"
    end

    if rc == FFI_OK then
        return true
    end

    -- rc == FFI_ERROR

    return nil, ffi_str(errmsg[0])
end


return _M
