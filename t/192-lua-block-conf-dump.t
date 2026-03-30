# vim:set ft= ts=4 sw=4 et fdm=marker:
# Tests for nginx -T (conf dump) completeness with large lua_block directives
# Regression test for https://github.com/openresty/lua-nginx-module/issues/2469

use Test::Nginx::Socket::Lua;

repeat_each(1);

plan tests => repeat_each() * (blocks() * 3);

$ENV{TEST_NGINX_HTML_DIR} ||= html_dir();

my $html_dir = $ENV{TEST_NGINX_HTML_DIR};
my $http_config = <<_EOC_;
    init_by_lua_block {
        function set_up_ngx_tmp_conf(conf)
            assert(os.execute("mkdir -p $html_dir/logs"))

            local conf_file = "$html_dir/nginx.conf"
            local f, err = io.open(conf_file, "w")
            if not f then
                ngx.log(ngx.ERR, err)
                return
            end

            assert(f:write(conf))
            f:close()

            return conf_file
        end

        function get_ngx_bin_path()
            local ffi = require "ffi"
            ffi.cdef[[char **ngx_argv;]]
            return ffi.string(ffi.C.ngx_argv[0])
        end
    }
_EOC_

add_block_preprocessor(sub {
    my $block = shift;

    if (!defined $block->http_config) {
        $block->set_value("http_config", $http_config);
    }

    if (!defined $block->request) {
        $block->set_value("request", "GET /t");
    }
});

env_to_nginx("PATH");
log_level("warn");
no_long_string();
run_tests();

__DATA__

=== TEST 1: nginx -T shows complete content of large content_by_lua_block (issue #2469)
--- config
    location = /t {
        content_by_lua_block {
            -- Build a large lua block that forces a second buffer refill during
            -- config parsing. The nginx config buffer is 4096 bytes, so we need
            -- content that spans past that boundary in the config file.
            local big_comment = string.rep("x", 4096)
            local conf = string.format([[
                pid logs/nginx_dump_test.pid;
                events {
                    worker_connections 64;
                }
                http {
                    server {
                        listen 18989;
                        location = /t {
                            content_by_lua_block {
                                -- %s
                                -- lua_block_conf_dump_marker_end
                                ngx.say("ok")
                            }
                        }
                    }
                }
            ]], big_comment)

            local conf_file = set_up_ngx_tmp_conf(conf)
            if not conf_file then
                ngx.say("FAIL: could not create conf file")
                return
            end

            local nginx = get_ngx_bin_path()

            -- First verify the config is valid
            local cmd = nginx .. " -p $TEST_NGINX_HTML_DIR -c " .. conf_file .. " -t 2>&1"
            local p = io.popen(cmd)
            local out = p:read("*a")
            p:close()

            if not out:find("test is successful") then
                ngx.say("FAIL: config test failed: " .. out)
                return
            end

            -- Now run nginx -T and check dump contains the full lua block
            cmd = nginx .. " -p $TEST_NGINX_HTML_DIR -c " .. conf_file .. " -T 2>&1"
            p = io.popen(cmd)
            out = p:read("*a")
            p:close()

            if out:find("lua_block_conf_dump_marker_end") then
                ngx.say("OK")
            else
                ngx.say("FAIL: marker not found in nginx -T output (truncated dump)")
            end
        }
    }
--- request
GET /t
--- response_body
OK
--- no_error_log
[error]
