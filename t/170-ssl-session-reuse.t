# vim:set ft= ts=4 sw=4 et fdm=marker:

use Cwd qw(abs_path realpath);
use File::Basename;

use Test::Nginx::Socket::Lua;

repeat_each(2);

sub resolve($$);

plan tests => repeat_each() * (blocks() * 2);

$ENV{TEST_NGINX_HTML_DIR} ||= html_dir();
$ENV{TEST_NGINX_MEMCACHED_PORT} ||= 11211;
$ENV{TEST_NGINX_RESOLVER} ||= '8.8.8.8';
$ENV{TEST_NGINX_SERVER_SSL_PORT} ||= 12345;
$ENV{TEST_NGINX_CERT_DIR} ||= dirname(realpath(abs_path(__FILE__)));
$ENV{TEST_NGINX_OPENRESTY_ORG_IP} ||= resolve("openresty.org", $ENV{TEST_NGINX_RESOLVER});

#log_level 'warn';
log_level 'debug';

no_long_string();
#no_diff();

sub read_file {
    my $infile = shift;
    open my $in, $infile
        or die "cannot open $infile for reading: $!";
    my $cert = do { local $/; <$in> };
    close $in;
    $cert;
}

sub resolve ($$) {
    my ($domain, $resolver) = @_;
    my $ips = qx/dig \@$resolver +short $domain/;

    my $exit_code = $? >> 8;
    if (!$ips || $exit_code != 0) {
        die "failed to resolve '$domain' using '$resolver' as resolver";
    }

    my ($ip) = split /\n/, $ips;
    return $ip;
}

our $DSTRootCertificate = read_file("t/cert/dst-ca.crt");
our $EquifaxRootCertificate = read_file("t/cert/equifax.crt");
our $TestCertificate = read_file("t/cert/test.crt");
our $TestCertificateKey = read_file("t/cert/test.key");
our $TestCRL = read_file("t/cert/test.crl");

run_tests();

__DATA__

=== TEST 1: www.google.com
access the public network is unstable, need a bigger timeout value.
--- quic_max_idle_timeout: 3
--- config
    server_tokens off;
    resolver $TEST_NGINX_RESOLVER ipv6=off;
    location /t {
        content_by_lua_block {
            local sock = ngx.socket.tcp()
            sock:settimeout(2000)
            local ok, err = sock:connect("www.google.com", 443)
            if not ok then
                ngx.say("failed to connect: ", err)
                return
            end

            ngx.say("connected: ", ok)

            local sess, err = sock:sslhandshake()
            if not sess then
                ngx.say("failed to do SSL handshake: ", err)
                return
            end

            ngx.say("ssl handshake: ", type(sess))

            local req = "GET / HTTP/1.1\r\nHost: www.google.com\r\nConnection: close\r\n\r\n"
            local bytes, err = sock:send(req)
            if not bytes then
                ngx.say("failed to send http request: ", err)
                return
            end

            ngx.say("sent http request: ", bytes, " bytes.")

            local line, err = sock:receive()
            if not line then
                ngx.say("failed to receive response status line: ", err)
                return
            end

            ngx.say("received: ", line)

            local sess, err = sock:getsslsession()
            if not sess then
                ngx.say("failed to get SSL session: ", err)
            else
                ngx.say("ssl session: ", type(sess))
            end

            local ok, err = sock:close()
            ngx.say("close: ", ok, " ", err)
        }
    }

--- request
GET /t
--- response_body_like chop
\Aconnected: 1
ssl handshake: cdata
sent http request: 59 bytes.
received: HTTP/1.1 (?:200 OK|302 Found)
ssl session: cdata
close: 1 nil
\z
--- timeout: 5



=== TEST 2: connect to nginx server
--- http_config
    server {
        listen $TEST_NGINX_SERVER_SSL_PORT ssl;
        server_name   test.com;
        ssl_certificate ../html/test.crt;
        ssl_certificate_key ../html/test.key;

        location / {
            content_by_lua_block {
                ngx.exit(201)
            }
        }
    }
--- config
    resolver $TEST_NGINX_RESOLVER ipv6=off;
    location /t {
        content_by_lua_block {
            local ssl_session

            local function http_req()
                local sock = ngx.socket.tcp()
                sock:settimeout(2000)
                local ok, err = sock:connect("127.0.0.1", $TEST_NGINX_SERVER_SSL_PORT)
                if not ok then
                    ngx.say("failed to connect: ", err)
                    return
                end

                ngx.say("connected: ", ok)

                ssl_session, err = sock:sslhandshake(ssl_session)
                if not ssl_session then
                    ngx.say("failed to do SSL handshake: ", err)
                    return
                end

                ngx.say("ssl handshake: ", type(ssl_session))
                ngx.say("ssl handshake: ", tostring(ssl_session))

                local req = "GET / HTTP/1.1\r\nHost: test.com\r\nConnection: close\r\n\r\n"
                local bytes, err = sock:send(req)
                if not bytes then
                    ngx.say("failed to send http request: ", err)
                    return
                end

                ngx.say("sent http request: ", bytes, " bytes.")

                local line, err = sock:receive()
                if not line then
                    ngx.say("failed to receive response status line: ", err)
                    return
                end

                ngx.say("received: ", line)

                ssl_session, err = sock:getsslsession()
                if ssl_session == nil then
                    ngx.say("failed to get SSL session: ", err)
                end
                local ok, err = sock:close()
                ngx.say("close: ", ok, " ", err)
            end

            http_req()
            http_req()
        }
    }

--- request
GET /t
--- response_body eval
qr/connected: 1
ssl handshake: cdata
ssl handshake: cdata<void \*>: 0x[0-9a-f]+
sent http request: 53 bytes.
received: HTTP\/1.1 201 Created
close: 1 nil
connected: 1
ssl handshake: cdata
ssl handshake: cdata<void \*>: 0x[0-9a-f]+
sent http request: 53 bytes.
received: HTTP\/1.1 201 Created
close: 1 nil
/
--- user_files eval
">>> test.key
$::TestCertificateKey
>>> test.crt
$::TestCertificate"
