# vim:set ft= ts=4 sw=4 et fdm=marker:
use lib 'lib';
use Test::Nginx::Socket;

#worker_connections(1014);
#master_on();
#workers(2);
#log_level('warn');

repeat_each(2);
#repeat_each(1);

plan tests => repeat_each() * (blocks() * 3);

#no_diff();
#no_long_string();
run_tests();

__DATA__

=== TEST 1: Set ETag
--- config
    location /t {
        content_by_lua '
            ngx.header["ETag"] = "123456789"
	    ngx.say(ngx.var.sent_http_etag)	
        ';
    }
--- request
GET /t
--- response_body
123456789
--- no_error_log
[error]

