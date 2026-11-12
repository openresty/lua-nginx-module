# vim:set ft= ts=4 sw=4 et fdm=marker:

use Test::Nginx::Socket::Lua;

repeat_each(2);

# server_name_resolver_by_lua_block needs the server_name_resolver hook of
# the nginx core.  A build without the hook contains the error message the
# directive is rejected with; replace this probe with an nginx version check
# once the hook is in an nginx release.
my $NginxBinary = $ENV{'TEST_NGINX_BINARY'} || 'nginx';
my $nginx_path = `sh -c 'command -v $NginxBinary'`;
chomp $nginx_path;

if (system("grep -q 'requires nginx with the server_name_resolver hook'"
           . " '$nginx_path'") == 0)
{
    plan(skip_all => "nginx core without the server_name_resolver hook");

} else {
    plan tests => repeat_each() * (blocks() * 3 + 6);
}

$ENV{TEST_NGINX_HTML_DIR} ||= html_dir();

our $Servers = <<'_EOC_';
    server {
        listen unix:$TEST_NGINX_HTML_DIR/nginx.sock default_server;
        server_name default.test;
        return 200 "server: $server_name\n";
    }

    server {
        listen unix:$TEST_NGINX_HTML_DIR/nginx.sock;
        server_name named.test;
        return 200 "server: $server_name\n";
    }

    server {
        listen unix:$TEST_NGINX_HTML_DIR/nginx.sock;
        server_name *.wild.test;
        return 200 "server: $server_name\n";
    }
_EOC_

our $Client = <<'_EOC_';
    location /t {
        content_by_lua_block {
            local function get(host)
                local sock = ngx.socket.tcp()
                sock:settimeout(2000)

                local ok, err = sock:connect(
                    "unix:$TEST_NGINX_HTML_DIR/nginx.sock")
                if not ok then
                    return "failed to connect: " .. err
                end

                local bytes, err = sock:send("GET / HTTP/1.0\r\nHost: "
                                             .. host .. "\r\n\r\n")
                if not bytes then
                    return "failed to send: " .. err
                end

                local res, err = sock:receive("*a")
                if not res then
                    return "failed to receive: " .. err
                end

                sock:close()

                return host .. " -> " .. (res:match("server: [^\n]*") or res)
            end

            for host in ngx.var.arg_hosts:gmatch("[^,]+") do
                ngx.say(get(host))
            end
        }
    }
_EOC_

no_long_string();

run_tests();

__DATA__

=== TEST 1: selection order: exact name, resolver, wildcard, default server
--- http_config eval
qq{
    server_name_resolver_by_lua_block {
        local host = ...
        ngx.log(ngx.WARN, "resolver called: ", host)

        if host == "alias.test" or host == "a.wild.test" then
            return "named.test"
        end
    }

$::Servers
}
--- config eval: $::Client
--- request
GET /t?hosts=named.test,alias.test,a.wild.test,b.wild.test,unknown.test
--- response_body
named.test -> server: named.test
alias.test -> server: named.test
a.wild.test -> server: named.test
b.wild.test -> server: *.wild.test
unknown.test -> server: default.test
--- grep_error_log eval: qr/resolver called: \S+/
--- grep_error_log_out
resolver called: alias.test
resolver called: a.wild.test
resolver called: b.wild.test
resolver called: unknown.test
--- no_error_log
[error]



=== TEST 2: an answer that is not an exact server_name, or not a string, is ignored
--- http_config eval
qq{
    server_name_resolver_by_lua_block {
        local host = ...

        if host == "alias.test" then
            return "x.wild.test"
        end

        if host == "other.test" then
            return "nosuch.test"
        end

        if host == "number.test" then
            return 42
        end

        if host == "false.test" then
            return false
        end

        if host == "empty.test" then
            return ""
        end
    }

$::Servers
}
--- config eval: $::Client
--- request
GET /t?hosts=alias.test,other.test,number.test,false.test,empty.test
--- response_body
alias.test -> server: default.test
other.test -> server: default.test
number.test -> server: default.test
false.test -> server: default.test
empty.test -> server: default.test
--- no_error_log
[error]



=== TEST 3: the host is passed in lower case and the answer is lowercased
--- http_config eval
qq{
    server_name_resolver_by_lua_block {
        local host = ...
        ngx.log(ngx.WARN, "resolver called: ", host)

        if host == "alias.test" then
            return "NAMED.test"
        end
    }

$::Servers
}
--- config eval: $::Client
--- request
GET /t?hosts=ALIAS.Test
--- response_body
ALIAS.Test -> server: named.test
--- grep_error_log eval: qr/resolver called: \S+/
--- grep_error_log_out
resolver called: alias.test
--- no_error_log
[error]



=== TEST 4: answering from a shared dict
--- http_config eval
qq{
    lua_shared_dict aliases 1m;

    init_by_lua_block {
        ngx.shared.aliases:set("alias.test", "named.test")
    }

    server_name_resolver_by_lua_block {
        return ngx.shared.aliases:get(...)
    }

$::Servers
}
--- config eval: $::Client
--- request
GET /t?hosts=alias.test,unknown.test
--- response_body
alias.test -> server: named.test
unknown.test -> server: default.test
--- no_error_log
[error]



=== TEST 5: a Lua error is logged and treated as a decline
--- http_config eval
qq{
    server_name_resolver_by_lua_block {
        error("resolver failed")
    }

$::Servers
}
--- config eval: $::Client
--- request
GET /t?hosts=alias.test
--- response_body
alias.test -> server: default.test
--- error_log
failed to run server_name_resolver_by_lua*
resolver failed
--- no_error_log
[alert]



=== TEST 6: yielding APIs are disabled
--- http_config eval
qq{
    server_name_resolver_by_lua_block {
        ngx.sleep(0.001)
        return "named.test"
    }

$::Servers
}
--- config eval: $::Client
--- request
GET /t?hosts=alias.test
--- response_body
alias.test -> server: default.test
--- error_log
API disabled in the context of server_name_resolver_by_lua*
--- no_error_log
[alert]



=== TEST 7: TLS: the resolver runs for the SNI name and not again for the same Host
--- http_config
    server_name_resolver_by_lua_block {
        local host = ...
        ngx.log(ngx.WARN, "resolver called: ", host)

        if host == "alias.test" then
            return "named.test"
        end
    }

    server {
        listen unix:$TEST_NGINX_HTML_DIR/nginx.sock ssl default_server;
        server_name default.test;
        ssl_certificate ../../cert/test2.crt;
        ssl_certificate_key ../../cert/test2.key;
        return 200 "server: $server_name\n";
    }

    server {
        listen unix:$TEST_NGINX_HTML_DIR/nginx.sock ssl;
        server_name named.test;
        ssl_certificate ../../cert/test.crt;
        ssl_certificate_key ../../cert/test.key;
        return 200 "server: $server_name\n";
    }
--- config
    location /t {
        content_by_lua_block {
            local sock = ngx.socket.tcp()
            sock:settimeout(2000)

            local ok, err = sock:connect(
                "unix:$TEST_NGINX_HTML_DIR/nginx.sock")
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            local sess, err = sock:sslhandshake(nil, "alias.test", false)
            if not sess then
                ngx.say("failed to do SSL handshake: ", err)
                return
            end

            for i = 1, 2 do
                local bytes, err = sock:send("GET / HTTP/1.1\r\n"
                                             .. "Host: alias.test\r\n\r\n")
                if not bytes then
                    ngx.say("failed to send: ", err)
                    return
                end

                local line, err
                repeat
                    line, err = sock:receive()
                until not line or line == ""

                line, err = sock:receive()
                ngx.say(line or err)
            end

            sock:close()
        }
    }
--- request
GET /t
--- response_body
server: named.test
server: named.test
--- grep_error_log eval: qr/resolver called: \S+/
--- grep_error_log_out
resolver called: alias.test
--- no_error_log
[error]



=== TEST 8: a duplicate directive is rejected
--- http_config
    server_name_resolver_by_lua_block {
        return nil
    }

    server_name_resolver_by_lua_block {
        return nil
    }
--- config
--- must_die
--- error_log
"server_name_resolver_by_lua_block" directive is duplicate
--- no_error_log
[alert]
