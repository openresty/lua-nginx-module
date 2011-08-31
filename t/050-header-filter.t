# vim:set ft= ts=4 sw=4 et fdm=marker:

use lib 'lib';
use Test::Nginx::Socket;

#worker_connections(1014);
#master_process_enabled(1);
#log_level('warn');

#repeat_each(2);
repeat_each(1);

plan tests => blocks() * repeat_each() * 3;

#no_diff();
#no_long_string();

run_tests();

__DATA__

=== TEST 1: set response content-type header
--- config
    location /read {
        echo "Hi";
        header_filter_by_lua '
            ngx.header.content_type = "text/my-plain";
        ';

    }
--- request
GET /read
--- response_headers
Content-Type: text/my-plain
--- response_body
Hi


