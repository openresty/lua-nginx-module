# vim:set ft= ts=4 sw=4 et fdm=marker:

use Test::Nginx::Socket::Lua;

# single-process mode (no master_on): an init_process failure exits
# the whole nginx with code 2, which --- must_die asserts

repeat_each(1);

$Test::Nginx::Util::DaemonEnabled = 'off';

plan tests => repeat_each() * (blocks() * 2 + 1);

no_long_string();
run_tests();

__DATA__

=== TEST 1: abort_on_error on + runtime error before yield exits with code 2
--- http_config
   lua_init_worker_abort_on_error on;
   init_worker_by_lua_block {
       error("boom")   -- runtime error before any yield
   }
--- config
   location /t {
       content_by_lua_block {
           ngx.say("never reached")
       }
   }
--- request
GET /t
--- must_die: 2
--- error_log
lua entry thread aborted:



=== TEST 2: exit_worker_by_lua is skipped when abort_on_error fires
--- http_config
   lua_init_worker_abort_on_error on;
   init_worker_by_lua_block {
       error("boom")   -- runtime error before any yield
   }
   exit_worker_by_lua_block {
       ngx.log(ngx.ERR, "EXIT_RAN")
   }
--- config
   location /t {
       content_by_lua_block {
           ngx.say("never reached")
       }
   }
--- request
GET /t
--- must_die: 2
--- error_log
lua entry thread aborted:
--- no_error_log
EXIT_RAN
