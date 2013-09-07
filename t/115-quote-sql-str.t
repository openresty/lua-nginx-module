# vim:set ft= ts=4 sw=4 et fdm=marker:

use lib 'lib';
use t::TestNginxLua;

repeat_each(2);

plan tests => repeat_each() * (blocks() * 3);

#log_level("warn");
no_long_string();

run_tests();

__DATA__

=== TEST 1: \0
--- config
    location = /set {
        content_by_lua '
            ngx.say(ngx.quote_sql_str("a\\0b\\0"))
        ';
    }
--- request
GET /set
--- response_body
'a\0b\0'
--- no_error_log
[error]

