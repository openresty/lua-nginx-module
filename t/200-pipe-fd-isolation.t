# vim:set ft= ts=4 sw=4 et fdm=marker:

use Test::Nginx::Socket::Lua;

repeat_each(1);

plan tests => repeat_each() * blocks() * 2;

no_long_string();

add_block_preprocessor(sub {
    my $block = shift;

    my $http_config = $block->http_config || '';
    $http_config .= <<'_EOC_';
    lua_package_path "../lua-resty-core/lib/?.lua;../lua-resty-lrucache/lib/?.lua;;";

    init_by_lua_block {
        require "resty.core"
    }
_EOC_
    $block->set_value("http_config", $http_config);
});

run_tests();

__DATA__

=== TEST 1: a later subprocess must not retain an earlier subprocess stdin
--- config
    location = /t {
        content_by_lua_block {
            local pipe = require("ngx.pipe")
            local first, err = pipe.spawn({"sh", "-c",
                                           "cat; printf stderr >&2"})
            assert(first, err)

            local bytes
            bytes, err = first:write("hello\n")
            assert(bytes, err)

            local second
            second, err = pipe.spawn({"sleep", "2"})
            assert(second, err)

            local ok
            ok, err = first:shutdown("stdin")
            assert(ok, err)

            first:set_timeouts(nil, 500, 500)
            local stdout
            stdout, err = first:stdout_read_all()
            assert(stdout and not err, err)

            local stderr
            stderr, err = first:stderr_read_all()
            assert(stderr and not err, err)

            ngx.print(stdout)
            ngx.say(stderr)
        }
    }
--- request
GET /t
--- response_body
hello
stderr
--- no_error_log
[error]
