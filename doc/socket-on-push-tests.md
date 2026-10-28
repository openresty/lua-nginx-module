# Socket push integration tests

Run from the repository root with a debug build of nginx containing this
checkout's ngx_lua module, matching lua-resty-core/lua-resty-lrucache on
`LUA_PATH`, the Perl `Test::Nginx` and `IPC::Run` modules, and Python 3:

```sh
TEST_NGINX_BINARY=/path/to/nginx prove -v t/190-socket-on-push.t
```

The test starts and stops its own Python standard-library TCP server on an
OS-assigned loopback port. No NATS server or other service is needed. Each
test parks a real Lua cosocket in nginx's keepalive pool, then uses a separate
control connection to trigger server pushes. Callback replies are checked by
the server. Reuse checks verify both the reuse counter and bidirectional IO
on the original connection.

Callbacks receive arbitrary chunks of a TCP byte stream, not application
messages. Tests explicitly cover a one-byte push, separated fragments, binary
data, and a payload larger than the read buffer, as well as reply/keep-open,
reply/close, callback failure, EOF, and the behavior without a callback. They
also check callback lifetime across request completion and pool checkout.

The `Socket on_push tests` GitHub Actions workflow builds the module with
nginx 1.27.1 and 1.29.4 on Ubuntu 22.04 and 24.04, runs each push case twice,
and runs the existing basic Lua sanity/content tests.
