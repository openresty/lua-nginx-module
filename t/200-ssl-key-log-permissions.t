# vim:set ft= ts=4 sw=4 et fdm=marker:

use Test::Nginx::Socket::Lua 'no_plan';

repeat_each(1);
no_shuffle();

my $old_umask = umask 0022;
add_cleanup_handler(sub { umask $old_umask; });

run_tests();

__DATA__

=== TEST 1: new SSL key log is owner-only
--- skip_openssl: 4: < 1.1.1
--- config
    lua_ssl_key_log sslkey.log;

    location /t {
        return 200 "ok\n";
    }
--- init
my $key_log = server_root() . "/conf/sslkey.log";
my $mode = (stat $key_log)[2];
defined $mode or die "failed to stat $key_log: $!";
$mode &= 0777;
die sprintf("unexpected key log mode %04o", $mode) unless $mode == 0600;
--- request
GET /t
--- response_body
ok
--- no_error_log
[error]
[alert]
[emerg]



=== TEST 2: broad existing SSL key log permissions are rejected
--- skip_openssl: 2: < 1.1.1
--- config
    lua_ssl_key_log ../html/sslkey.log;

    location /t {
        return 200;
    }
--- user_files
>>> sslkey.log
existing key log
--- request
GET /t
--- must_die
--- error_log eval
qr/\[emerg\].*the SSL key log file ".*sslkey\.log" must have owner-only permissions/
