Todo
====

* Add directives to run lua codes when nginx stops/reloads
* Implement ngx.exec() functionality
* Deal with TCP 3-second delay problem under great connection harness

Future Plan
===========

* Add 'lua_require' directive to load module into main thread's globals
* Add Lua VM passive yield and resume (using debug hook)
* Make set_by_lua using the same mechanism as content_by_lua
* Integrate $request_body reading functionality

