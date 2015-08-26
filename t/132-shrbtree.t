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

=== TEST 1: string key, int value
--- http_config
    lua_shared_rbtree rbtree 1m;
--- config
    location = /test {
        content_by_lua '
            local cmp = function(s1, s2)
                if s1 > s2 then
                    return 1

                elseif s1 < s2 then
                    return -1

                else
                    return 0
                end 
            end
            local rbtree = ngx.shrbtree.rbtree
            rbtree:insert{"a", 1, cmp}
            rbtree:insert{"b", 12, cmp}
            rbtree:insert{"c", 123, cmp}
            rbtree:insert{"d", 1234, cmp}
            rbtree:insert{"e", 12345, cmp}

            local val
            val = rbtree:get{"a", cmp}
            ngx.say(val, " ", type(val))
            val = rbtree:get{"b", cmp}
            ngx.say(val, " ", type(val))
            val = rbtree:get{"c", cmp}
            ngx.say(val, " ", type(val))
            val = rbtree:get{"d", cmp}
            ngx.say(val, " ", type(val))
            val = rbtree:get{"e", cmp}
            ngx.say(val, " ", type(val))
        ';
    }
--- request
GET /test
--- response_body
1 number
12 number
123 number
1234 number
12345 number
--- no_error_log
[error]

=== TEST 2: string key, float-point value
--- http_config
    lua_shared_rbtree rbtree 1m;
--- config
    location = /test {
        content_by_lua '
            local cmp = function(s1, s2)
                if s1 > s2 then
                    return 1

                elseif s1 < s2 then
                    return -1

                else
                    return 0
                end

            end
            local rbtree = ngx.shrbtree.rbtree
            rbtree:insert{"a", 0.1, cmp}
            rbtree:insert{"b", 0.12, cmp}
            rbtree:insert{"c", 0.123, cmp}
            rbtree:insert{"d", 0.1234, cmp}
            rbtree:insert{"e", 0.12345, cmp}

            local val
            val = rbtree:get{"a", cmp}
            ngx.say(val, " ", type(val))
            val = rbtree:get{"b", cmp}
            ngx.say(val, " ", type(val))
            val = rbtree:get{"c", cmp}
            ngx.say(val, " ", type(val))
            val = rbtree:get{"d", cmp}
            ngx.say(val, " ", type(val))
            val = rbtree:get{"e", cmp}
            ngx.say(val, " ", type(val))
        ';
    }
--- request
GET /test
--- response_body
0.1 number
0.12 number
0.123 number
0.1234 number
0.12345 number
--- no_error_log
[error]

=== TEST 3: number key, string value
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
            
            local rbtree = ngx.shrbtree.rbtree
            rbtree:insert{1, "s", cmp}
            rbtree:insert{2, "ss", cmp}
            rbtree:insert{3, "sss", cmp}
            rbtree:insert{4, "ssss", cmp}
            rbtree:insert{5, "sssss", cmp}

            local val
            val = rbtree:get{1, cmp}
            ngx.say(val, " ", type(val))
            val = rbtree:get{2, cmp}
            ngx.say(val, " ", type(val))
            val = rbtree:get{3, cmp}
            ngx.say(val, " ", type(val))
            val = rbtree:get{4, cmp}
            ngx.say(val, " ", type(val))
            val = rbtree:get{5, cmp}
            ngx.say(val, " ", type(val))
        ';
    }
--- request
GET /test
--- response_body
s string
ss string
sss string
ssss string
sssss string

--- no_error_log
[error]

=== TEST 4: table key, number/string value
--- http_config
    lua_shared_rbtree rbtree 1m;
--- config
    location = /test {
        content_by_lua '
            local cmp = function(a, b)
                local x
                if type(a) == "table" then
                    x = a[1]
                else
                    x= a
                end

                if x > b[2] then
                    return 1

                elseif x < b[1] then
                    return -1

                else
                    return 0
                end
            end

            local rbtree = ngx.shrbtree.rbtree
            local node = {}

            node[1] = {1, 3}
            node[2] = "string"
            node[3] = cmp
            rbtree:insert(node)

            node[1] = {4, 6}
            node[2] = 1234
            node[3] = cmp
            rbtree:insert(node)

            node[1] = {7, 9}
            node[2] = "gnirts"
            node[3] = cmp
            rbtree:insert(node)

            node[1] = {11, 19}
            node[2] = 4321
            node[3] = cmp
            rbtree:insert(node)

            local val
            val = rbtree:get{3, cmp}
            ngx.say(val, " ", type(val))
            val = rbtree:get{5, cmp}
            ngx.say(val, " ", type(val))
            val = rbtree:get{7, cmp}
            ngx.say(val, " ", type(val))
            val = rbtree:get{19, cmp}
            ngx.say(val, " ", type(val))
            val = rbtree:get{20, cmp}
            ngx.say(val, " ", type(val))
        ';
    }
--- request
GET /test
--- response_body
string string
1234 number
gnirts string
4321 number
nil nil
--- no_error_log
[error]

=== TEST 5: number key, table value
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

            local rbtree = ngx.shrbtree.rbtree
            local node = {}

            node[1] = 10
            node[2] = {1, 2, 3, "4", "5", {1, 2, {1, 2}}}
            node[3] = cmp
            rbtree:insert(node)

            node[1] = 111
            node[2] = {is_false = false, is_true = true}
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

=== TEST 6: table key, table value
--- http_config
    lua_shared_rbtree rbtree 1m;
--- config
    location = /test {
        content_by_lua '
            local cmp = function(a, b)
                local x
                if type(a) == "table" then
                    x = a[1]
                else
                    x= a
                end

                if x > b[2] then
                    return 1

                elseif x < b[1] then
                    return -1

                else
                    return 0
                end
            end

            local rbtree = ngx.shrbtree.rbtree
            local node = {}

            node[1] = {1, 3}
            node[2] = {1, 2, 3, "4", "5"}
            node[3] = cmp
            rbtree:insert(node)

            node[1] = {4, 6}
            node[2] = {k1 = "v1", k2="v2", k3="v3"}
            node[3] = cmp
            rbtree:insert(node)

            node[1] = {7, 9}
            node[2] = {1, "2", {3, "4", 5}}
            node[3] = cmp
            rbtree:insert(node)

            node[1] = {11, 19}
            node[2] = {{1, 2, 3}, {"1", "2", "3"}}
            node[3] = cmp
            rbtree:insert(node)

            local val
            val = rbtree:get{3, 1, cmp}
            ngx.say(val, " ", type(val))
            val = rbtree:get{3, 4,  cmp}
            ngx.say(val, " ", type(val))

            val = rbtree:get{5, "k1", cmp}
            ngx.say(val, " ", type(val))
            val = rbtree:get{{4, 6}, "k3", cmp}
            ngx.say(val, " ", type(val))

            val = rbtree:get{7, 3, cmp}
            ngx.say(val[2], " ", type(val[2]))
            val = rbtree:get{19, 1, cmp}
            ngx.say(val[1], " ", type(val[1]))

        ';
    }
--- request
GET /test
--- response_body
1 number
4 string
v1 string
v3 string
4 string
1 number
--- no_error_log
[error]

=== TEST 7: multi shrbtree
--- http_config
    lua_shared_rbtree rbtree1 1m;
    lua_shared_rbtree rbtree2 1m;
    lua_shared_rbtree rbtree3 1m;
--- config
    location = /test {
        content_by_lua '
            local cmp = function(s1, s2)
                if s1 > s2 then
                    return 1

                elseif s1 < s2 then
                    return -1

                else
                    return 0
                end

            end
            local rbtree1 = ngx.shrbtree.rbtree1
            local rbtree2 = ngx.shrbtree.rbtree2
            local rbtree3 = ngx.shrbtree.rbtree3

            rbtree1:insert{"a", 11, cmp}
            rbtree1:insert{"b", 112, cmp}
            rbtree1:insert{"c", 1123, cmp}
            rbtree2:insert{"a", 21, cmp}
            rbtree2:insert{"b", 212, cmp}
            rbtree2:insert{"c", 2123, cmp}
            rbtree3:insert{"a", 31, cmp}
            rbtree3:insert{"b", 312, cmp}
            rbtree3:insert{"c", 3123, cmp}

            local val
            val = rbtree1:get{"a", cmp}
            ngx.say(val, " ", type(val))
            val = rbtree2:get{"b", cmp}
            ngx.say(val, " ", type(val))
            val = rbtree3:get{"c", cmp}
            ngx.say(val, " ", type(val))
        ';
    }
--- request
GET /test
--- response_body
11 number
212 number
3123 number
--- no_error_log
[error]

=== TEST 8: manay nodes
--- http_config
    lua_shared_rbtree rbtree 10m;
--- config
    location = /test {
        content_by_lua '
            local cmp = function(a, b)
                local x
                if type(a) == "table" then
                    x = a[1]
                else
                    x= a
                end

                if x > b[2] then
                    return 1

                elseif x < b[1] then
                    return -1

                else
                    return 0
                end
            end

            local rbtree = ngx.shrbtree.rbtree

            local node = {}
            node[3] = cmp
            for i = 1, 1000, 1 do
                node[1] = {(i-1)*10+1, i*10}
                node[2] = {k1 = 1, k2 = 2, k3 = 3}
                rbtree:insert(node)
            end

            for i = 1, 1000, 1 do
                val = rbtree:get{(i-1)*10+1, "k1", cmp}
                if not val == 1 then
                    ngx.say("error")
                end
            end
            ngx.say("ok")
        ';
    }
--- request
GET /test
--- response_body
ok
--- no_error_log
[error]

=== TEST 9: "shared dict" and "shared shrbtree" conflict test
--- http_config
    lua_shared_dict     shdict   1m;
    lua_shared_rbtree   shrbtree 1m;
--- config
    location = /test {
        content_by_lua '
            local dict = ngx.shared.shdict
            dict:set("Jim", 8)
            dict:set("Tim", 9)
            dict:set("Lim", 10)

            local cmp = function(s1, s2)
                if s1 > s2 then
                    return 1

                elseif s1 < s2 then
                    return -1

                else
                    return 0
                end 
            end

            local rbtree = ngx.shrbtree.shrbtree
            rbtree:insert{"Jim", 8,  cmp}
            rbtree:insert{"Tim", 9,  cmp}
            rbtree:insert{"Lim", 10, cmp}
            
            local val
            val = rbtree:get{"Jim", cmp}
            ngx.say(val, " ", type(val))
            val = rbtree:get{"Tim", cmp}
            ngx.say(val, " ", type(val))
            val = rbtree:get{"Lim", cmp}
            ngx.say(val, " ", type(val))
           
            val = dict:get("Jim")
            ngx.say(val, " ", type(val))
            val = dict:get("Tim")
            ngx.say(val, " ", type(val))
            val = dict:get("Lim")
            ngx.say(val, " ", type(val))
        ';
    }
--- request
GET /test
--- response_body
8 number
9 number
10 number
8 number
9 number
10 number
--- no_error_log
[error]

=== TEST 10: delete function
--- http_config
    lua_shared_rbtree rbtree 10m;
--- config
    location = /test {
        content_by_lua '
            local cmp = function(a, b)
                local x
                if type(a) == "table" then
                    x = a[1]
                else
                    x= a
                end

                if x > b[2] then
                    return 1

                elseif x < b[1] then
                    return -1

                else
                    return 0
                end
            end

            local rbtree = ngx.shrbtree.rbtree

            local node = {}
            node[3] = cmp
            for i = 1, 1000, 1 do
                node[1] = {(i-1)*10+1, i*10}
                node[2] = {k1 = 1, k2 = 2, k3 = 3}
                rbtree:insert(node)
            end

            val = rbtree:get{123, "k2", cmp}
            ngx.say(val, " ", type(val))

            for i = 1, 1000, 2 do
                if not rbtree:delete{(i-1)*10+1, cmp} then
                    print("error")
                end
            end

            val = rbtree:get{123, "k2", cmp}
            ngx.say(val, " ", type(val))

            for i = 1, 1000, 2 do
                val = rbtree:get{(i-1)*10+1, "k3", cmp}
                if not val == nil then
                    ngx.say("error");
                end
            end
            
            for i = 2, 1000, 2 do
                val = rbtree:get{(i-1)*10+1, "k1", cmp}
                if not val == 1 then
                    ngx.say("error");
                end
            end
            ngx.say("ok")
        ';
    }
--- request
GET /test
--- response_body
2 number
nil nil
ok
--- no_error_log
[error]
