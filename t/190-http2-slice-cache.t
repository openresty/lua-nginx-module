# vim:set ft= ts=4 sw=4 et fdm=marker:
#
# Regression test for the nginx "http2_subreq_error_wakeup" patch
# (openresty/openresty patches/nginx/*/nginx-*-http2_subreq_error_wakeup.patch).
#
# The patch makes ngx_http_finalize_request() skip ngx_http_terminate_request()
# for HTTP/2 subrequests on the error / timeout path and wake the parent request
# instead.  Its guard only checks `r->http_version >= NGX_HTTP_VERSION_20`, so it
# also catches *native* nginx subrequests that have no post_subrequest handler --
# most notably the range subrequests created by the ngx_http_slice_module.
#
# As reported in openresty/openresty#1131, when such a slice subrequest hits an
# error (e.g. a send_timeout while streaming to a slow HTTP/2 client) the patched
# code falls through to ngx_http_special_response_handler(), which tries to send a
# response header on a subrequest that has already sent its 206 header, producing
# a flood of:
#
#     [alert] ... header already sent while ...
#
# and the send timer re-arms on every interval.
#
# These tests drive slice + proxy_cache over HTTP/2 with realistic (1 MiB) slices
# of multi-megabyte resources, so each slice subrequest actually streams a large
# body, and assert that the worker never logs the "header already sent" alert and
# never crashes.  They are scenario guards: depending on the nginx version the
# exact send_timeout race may or may not fire, but any regression that drives a
# slice subrequest into the special-response path over HTTP/2 will surface here.

use Test::Nginx::Socket::Lua;
use Cwd qw(abs_path realpath);
use File::Basename;

$ENV{TEST_NGINX_HTML_DIR} ||= html_dir();

log_level('info');

repeat_each(2);

# Skip the whole file when the nginx under test was built without the
# ngx_http_slice_module (the `slice` directive would otherwise abort startup).
my $nginx_bin = $ENV{TEST_NGINX_BINARY} || 'nginx';
my $nginx_v = `$nginx_bin -V 2>&1`;
if ($ENV{MOCKEAGAIN}) {
    plan(skip_all => "requires multi-megabyte slice transfers");
} elsif ($nginx_v !~ /--with-http_slice_module/) {
    plan(skip_all => "nginx built without --with-http_slice_module");
} else {
    # per repeat: TEST 1 => 7, TEST 2 => 4, TEST 3 => 6
    plan tests => repeat_each() * 17;
}

no_long_string();
run_tests();

__DATA__

=== TEST 1: slice + proxy_cache over HTTP/2, full multi-slice (1m) download
--- http_config
    proxy_cache_path $TEST_NGINX_HTML_DIR/cache keys_zone=slicezone:1m;

    server {
        listen unix:$TEST_NGINX_HTML_DIR/origin.sock;

        location / {
            content_by_lua_block {
                local total = 3 * 1024 * 1024   -- 3 slices of 1m
                local range = ngx.req.get_headers()["Range"] or ""
                local s, e = range:match("bytes=(%d+)%-(%d+)")
                s = tonumber(s) or 0
                e = tonumber(e) or (total - 1)
                if e > total - 1 then e = total - 1 end
                ngx.status = 206
                ngx.header["Content-Range"] =
                    string.format("bytes %d-%d/%d", s, e, total)
                ngx.header["Accept-Ranges"] = "bytes"
                ngx.print(string.rep("A", e - s + 1))
            }
        }
    }
--- config
    location /slice {
        slice 1m;
        proxy_cache slicezone;
        proxy_cache_key $uri$slice_range;
        proxy_set_header Range $slice_range;
        proxy_cache_valid 206 1m;
        proxy_pass http://unix:$TEST_NGINX_HTML_DIR/origin.sock:/;
    }
--- http2
--- request
GET /slice
--- response_headers
Content-Length: 3145728
--- response_body eval
"A" x (3 * 1024 * 1024)
--- no_error_log
[alert]
[crit]
[error]
header already sent



=== TEST 2: slice subrequest errors mid-stream over HTTP/2 (origin aborts a later slice)
--- http_config
    proxy_cache_path $TEST_NGINX_HTML_DIR/cache2 keys_zone=slicezone2:1m;

    server {
        listen unix:$TEST_NGINX_HTML_DIR/origin2.sock;

        location / {
            content_by_lua_block {
                local total = 3 * 1024 * 1024
                local range = ngx.req.get_headers()["Range"] or ""
                local s, e = range:match("bytes=(%d+)%-(%d+)")
                s = tonumber(s) or 0
                e = tonumber(e) or (total - 1)
                if e > total - 1 then e = total - 1 end

                if s == 0 then
                    -- first slice: stream a full 1m body so the slice module
                    -- continues to the next slice.
                    ngx.status = 206
                    ngx.header["Content-Range"] =
                        string.format("bytes %d-%d/%d", s, e, total)
                    ngx.header["Accept-Ranges"] = "bytes"
                    ngx.print(string.rep("A", e - s + 1))
                    return
                end

                -- a later slice subrequest: abort the connection so the slice
                -- subrequest finalizes with an error while the parent HTTP/2
                -- request is still active.
                ngx.exit(444)
            }
        }
    }
--- config
    location /slice {
        slice 1m;
        proxy_cache slicezone2;
        proxy_cache_key $uri$slice_range;
        proxy_set_header Range $slice_range;
        proxy_cache_valid 206 1m;
        proxy_pass http://unix:$TEST_NGINX_HTML_DIR/origin2.sock:/;
    }
--- http2
--- request
GET /slice
--- ignore_response
--- no_error_log
[alert]
[crit]
[emerg]
header already sent



=== TEST 3: slice + proxy_cache over HTTP/2 with a short send_timeout
--- http_config
    proxy_cache_path $TEST_NGINX_HTML_DIR/cache3 keys_zone=slicezone3:1m;

    server {
        listen unix:$TEST_NGINX_HTML_DIR/origin3.sock;

        location / {
            content_by_lua_block {
                local total = 3 * 1024 * 1024
                local range = ngx.req.get_headers()["Range"] or ""
                local s, e = range:match("bytes=(%d+)%-(%d+)")
                s = tonumber(s) or 0
                e = tonumber(e) or (total - 1)
                if e > total - 1 then e = total - 1 end
                ngx.status = 206
                ngx.header["Content-Range"] =
                    string.format("bytes %d-%d/%d", s, e, total)
                ngx.header["Accept-Ranges"] = "bytes"
                ngx.print(string.rep("A", e - s + 1))
            }
        }
    }
--- config
    send_timeout 1s;

    location /slice {
        slice 1m;
        proxy_cache slicezone3;
        proxy_cache_key $uri$slice_range;
        proxy_set_header Range $slice_range;
        proxy_cache_valid 206 1m;
        proxy_pass http://unix:$TEST_NGINX_HTML_DIR/origin3.sock:/;
    }
--- http2
--- request
GET /slice
--- response_headers
Content-Length: 3145728
--- response_body_like: ^A+$
--- no_error_log
[alert]
[crit]
header already sent
