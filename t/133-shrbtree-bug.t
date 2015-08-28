# vim:set ft= ts=4 sw=4 et fdm=marker:
use lib 'lib';
use Test::Nginx::Socket::Lua;

#worker_connections(1014);
#master_process_enabled(1);
#log_level('warn');

#repeat_each(2);

plan tests => repeat_each() * (blocks() * 3 );

#no_diff();
no_long_string();
#master_on();
#workers(2);

run_tests();

__DATA__

=== TEST 1: number key, table value(It's no error to "curl localhost/test", when conf in "nginx.conf")
--- http_config
    lua_shared_rbtree rbtree 1m;
--- config
    location = /test {
        content_by_lua '
            local cmp = function(a, b)
                if a > b then
                    return 1

                elseif a < b then
                    return -1

                else
                    return 0
                end

            end

            local rbtree = ngx.shared.rbtree
            local node = {}

            node[1] = 10
            node[2] = {1, 2, 3, "4", "5", {1, 2, {1, 2}}}
            node[3] = cmp
            rbtree:insert(node)

            node[1] = 11
            node[2] = {k1 = "v1", k2="v2", k3="v3"}
            node[3] = cmp
            rbtree:insert(node);

            node[1] = 12.34
            node[2] = {1, "2", {3, "4", 5}, {"aa", "bb", "cc", {1, 2, 3}}} 
            node[3] = cmp
            rbtree:insert(node);

            node[1] = 111
            node[2] = {is_false = false, is_true = true}
            node[3] = cmp
            rbtree:insert(node)

            local val
            val = rbtree:get{10, 1, cmp}
            ngx.say(val, " ", type(val))
            val = rbtree:get{10, 4, cmp}
            ngx.say(val, " ", type(val))
            val = rbtree:get{10, 6, cmp}
            ngx.say(val[3][2], " ", type(val[3][2]))
            
            val = rbtree:get{11, "k1", cmp}
            ngx.say(val, " ", type(val))
            
            val = rbtree:get{12.34, cmp}

            ngx.say(val[1], " ", type(val[1]))
            ngx.say(val[4][4][1], " ", type(val[4][4][1]))

            val = rbtree:get{111, "is_false", cmp}
            ngx.say(val, " ", type(val))
            val = rbtree:get{111, "is_true", cmp}
            ngx.say(val, " ", type(val))
        ';
    }
--- request
GET /test
--- response_body
1 number
4 string
2 number
v1 string
1 number
1 number
false boolean
true boolean
--- no_error_log
[error]
