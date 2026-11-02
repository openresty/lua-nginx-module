use Test::Nginx::Socket::Lua;

repeat_each(2);
plan tests => repeat_each() * blocks() * 3;

add_block_preprocessor(sub {
    my $block = shift;
    $block->set_value('http_config', <<'EOC');
    lua_shared_dict locks 1m;

    init_by_lua_block {
        local ffi = require "ffi"
        ffi.cdef[[
            int ngx_http_lua_ffi_shdict_compare_expire(void *zone,
                const unsigned char *key, size_t key_len,
                const unsigned char *value, size_t value_len, long exptime);
        ]]

        function compare_expire(dict, key, value, exptime)
            local zone = ffi.C.ngx_http_lua_ffi_shdict_udata_to_zone(dict[1])
            return ffi.C.ngx_http_lua_ffi_shdict_compare_expire(
                       zone, key, #key, value, #value, exptime)
        end
    }
EOC
});

no_long_string();
run_tests();

__DATA__

=== TEST 1: renew a matching token and preserve its value and flags
--- config
    location = /t {
        content_by_lua_block {
            local dict = ngx.shared.locks
            dict:set("lock", "owner", 1, 42)
            ngx.say(compare_expire(dict, "lock", "owner", 5000))
            local value, flags = dict:get("lock")
            ngx.say(value, ":", flags)
            local ttl = dict:ttl("lock")
            ngx.say(ttl > 4 and ttl <= 5)
        }
    }
--- request
GET /t
--- response_body
0
owner:42
true
--- no_error_log
[error]



=== TEST 2: reject mismatching tokens and non-string values
--- config
    location = /t {
        content_by_lua_block {
            local dict = ngx.shared.locks
            dict:set("lock", "owner")
            ngx.say(compare_expire(dict, "lock", "other", -1))
            ngx.say(compare_expire(dict, "lock", "own", 1000))
            ngx.say(dict:get("lock"), ":", dict:ttl("lock"))
            dict:set("number", 123)
            dict:set("boolean", true)
            dict:lpush("list", "owner")
            ngx.say(compare_expire(dict, "number", "123", -1))
            ngx.say(compare_expire(dict, "boolean", "true", -1))
            ngx.say(compare_expire(dict, "list", "owner", -1))
            ngx.say(dict:get("number"), ":", dict:get("boolean"))
            ngx.say(dict:lpop("list"))
        }
    }
--- request
GET /t
--- response_body
-5
-5
owner:0
-5
-5
-5
123:true
owner
--- no_error_log
[error]



=== TEST 3: deletion frees the node and allows the key to be reused
--- config
    location = /t {
        content_by_lua_block {
            local dict = ngx.shared.locks
            local free = dict:free_space()
            local token = string.rep("x", 8192)
            for i = 1, 100 do
                local ok, err = dict:safe_add("lock", token)
                if not ok then
                    error(err)
                end

                if compare_expire(dict, "lock", token, -1) ~= 0 then
                    error("failed to delete matching owner")
                end
            end

            ngx.say(dict:get("lock"))
            ngx.say(#dict:get_keys(0))
            ngx.say(dict:free_space() == free)
            ngx.say(compare_expire(dict, "lock", token, -1))
            ngx.say(dict:add("lock", "next"))
            ngx.say(dict:get("lock"))
            ngx.say(compare_expire(dict, "lock", "next", -1))
        }
    }
--- request
GET /t
--- response_body
nil
0
true
-5
truenilfalse
next
0
--- no_error_log
[error]



=== TEST 4: expired and replaced owners cannot renew or delete a lock
--- config
    location = /t {
        content_by_lua_block {
            local dict = ngx.shared.locks
            dict:set("lock", "old", 0.02)
            ngx.sleep(0.03)
            ngx.say(compare_expire(dict, "lock", "old", 1000))
            ngx.say(compare_expire(dict, "lock", "old", -1))
            ngx.say(dict:get("lock"))
            ngx.say(dict:add("lock", "new", 10))
            ngx.say(compare_expire(dict, "lock", "old", -1))
            ngx.say(compare_expire(dict, "lock", "old", 1000))
            ngx.say(dict:get("lock"))
            ngx.say(dict:ttl("lock") > 9)
            ngx.say(compare_expire(dict, "lock", "new", -1))
            ngx.say(dict:get("lock"))
        }
    }
--- request
GET /t
--- response_body
-5
-5
nil
truenilfalse
-5
-5
new
true
0
nil
--- no_error_log
[error]



=== TEST 5: zero expiry, empty tokens, and binary keys and tokens
--- config
    location = /t {
        content_by_lua_block {
            local dict = ngx.shared.locks
            dict:set("lock", "", 1)
            ngx.say(compare_expire(dict, "lock", "", 0))
            ngx.say(dict:ttl("lock"))
            ngx.say(compare_expire(dict, "lock", "", -1))
            local key = "lock\0key"
            local token = "owner\0token"
            dict:set(key, token)
            ngx.say(compare_expire(dict, key, "owner\0other", -1))
            ngx.say(dict:get(key) == token)
            ngx.say(compare_expire(dict, key, token, -1))
            ngx.say(dict:get(key))
        }
    }
--- request
GET /t
--- response_body
0
0
0
-5
true
0
nil
--- no_error_log
[error]



=== TEST 6: native argument guards reject invalid inputs
--- config
    location = /t {
        content_by_lua_block {
            local ffi = require "ffi"
            local dict = ngx.shared.locks
            local zone = ffi.C.ngx_http_lua_ffi_shdict_udata_to_zone(dict[1])
            local compare = ffi.C.ngx_http_lua_ffi_shdict_compare_expire
            ngx.say(compare(nil, "k", 1, "v", 1, -1))
            ngx.say(compare(zone, nil, 1, "v", 1, -1))
            ngx.say(compare(zone, "", 0, "v", 1, -1))
            ngx.say(compare(zone, string.rep("k", 65536), 65536, "v", 1, -1))
            ngx.say(compare(zone, "k", 1, nil, 0, -1))
            ngx.say(compare(zone, "k", 1, "v", 1, -2))
            dict:set("k", "v")
            ngx.say(compare_expire(dict, "k", "v", -1))
        }
    }
--- request
GET /t
--- response_body
-1
-1
-1
-1
-1
-1
0
--- no_error_log
[error]
