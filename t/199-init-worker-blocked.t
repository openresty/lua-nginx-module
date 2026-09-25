# vim:set ft= ts=4 sw=4 et fdm=marker:

use strict;
use warnings;
use FindBin;
use Test::More;

# Manual lifecycle tests: the worker stays blocked inside init_worker,
# so it never serves requests and the Test::Nginx block cycle cannot apply.

my $Nginx    = $ENV{TEST_NGINX_BINARY} || "$FindBin::Bin/../work/nginx/sbin/nginx";
my $Port     = 19847;
my $MemcPort = $ENV{TEST_NGINX_MEMCACHED_PORT} || 11211;

sub run_one {
    my ($name, $abort) = @_;

    my $dir = "/tmp/init-worker-blocked-$name";
    system("rm -rf $dir && mkdir -p $dir/logs");

    open my $fh, '>', "$dir/nginx.conf" or die "write conf: $!";
    printf $fh <<'EOF', $dir, $dir, $abort, $MemcPort, $Port;
worker_processes 1;
master_process off;
daemon on;
error_log %s/logs/error.log warn;
pid %s/logs/nginx.pid;
events { worker_connections 64; }
http {
    lua_init_worker_abort_on_error %s;
    init_worker_by_lua_block {
        local sock = ngx.socket.tcp()
        local ok = sock:connect("127.0.0.1", %d)
        if not ok then
            return
        end
        sock:send("get")
        sock:receive()
    }
    server { listen %d; location /t { return 200 "ok"; } }
}
EOF
    close $fh;

    system("$Nginx -p $dir -c nginx.conf") == 0
        or die "nginx failed to start";

    sleep 2;

    open my $pf, '<', "$dir/logs/nginx.pid" or die "no pid file: $!";
    chomp(my $pid = <$pf>);
    close $pf;

    my $alive = kill 0, $pid;

    open my $lf, '<', "$dir/logs/error.log" or die "no error log: $!";
    my $log = do { local $/; <$lf> };
    close $lf;

    ok($alive, "$name: worker still blocked (alive) after 2s");
    unlike($log, qr/timed out/, "$name: no timeout fired (budget is infinite)");

    kill 'TERM', $pid;
    sleep 1;
    kill 'KILL', $pid;
}

sub run_signal {
    my ($name, $signal) = @_;

    my $dir = "/tmp/init-worker-blocked-$name";
    system("rm -rf $dir && mkdir -p $dir/logs");

    open my $fh, '>', "$dir/nginx.conf" or die "write conf: $!";
    printf $fh <<'EOF', $dir, $dir, $MemcPort, $Port + 1;
worker_processes 1;
master_process off;
daemon off;
error_log %s/logs/error.log warn;
pid %s/logs/nginx.pid;
events { worker_connections 64; }
http {
    init_worker_by_lua_block {
        local sock = ngx.socket.tcp()
        local ok = sock:connect("127.0.0.1", %d)
        if not ok then
            return
        end
        sock:send("get")
        sock:receive()
    }
    server { listen %d; location /t { return 200 "ok"; } }
}
EOF
    close $fh;

    my $pid = fork();
    die "fork: $!" unless defined $pid;

    if ($pid == 0) {
        exec $Nginx, '-p', $dir, '-c', 'nginx.conf';
        die "exec: $!";
    }

    sleep 1;               # let init_worker reach the stalled read inside the pump

    kill $signal, $pid;    # deliver the signal mid-yield

    waitpid($pid, 0);
    my $sig  = $? & 127;   # 0 = exited by itself, nonzero = killed by that signal
    my $code = $? >> 8;

    open my $lf, '<', "$dir/logs/error.log" or die "no error log: $!";
    my $log = do { local $/; <$lf> };
    close $lf;

    like($log, qr/aborted by signal/, "$name: pump noticed the signal and bailed out");
    is($sig, 0, "$name: exited by itself, not killed by the signal");
    is($code, 0, "$name: clean exit code");
}


sub run_frozen_timer_signal {
    my ($name, $signal) = @_;

    my $dir = "/tmp/init-worker-blocked-$name";
    system("rm -rf $dir && mkdir -p $dir/logs");

    open my $fh, '>', "$dir/nginx.conf" or die "write conf: $!";
    printf $fh <<'CONF', $dir, $dir, $MemcPort, $Port + 2;
worker_processes 1;
master_process off;
daemon off;
error_log %s/logs/error.log warn;
pid %s/logs/nginx.pid;
events { worker_connections 64; }
http {
    init_worker_by_lua_block {
        ngx.shared.iw_state:set("cb_ran", 0)
        ngx.timer.at(0, function(premature)
            ngx.log(ngx.WARN, "frozen timer fired, premature=", premature)
        end)
        local sock = ngx.socket.tcp()
        local ok = sock:connect("127.0.0.1", %d)
        if not ok then
            return
        end
        sock:send("get")
        sock:receive()
    }
    lua_shared_dict iw_state 1m;
    server { listen %d; location /t { return 200 "ok"; } }
}
CONF
    close $fh;

    my $pid = fork();
    die "fork: $!" unless defined $pid;

    if ($pid == 0) {
        exec $Nginx, '-p', $dir, '-c', 'nginx.conf';
        die "exec: $!";
    }

    sleep 1;               # timer is frozen; the stalled read holds the pump

    kill $signal, $pid;    # signal fires mid-pump

    waitpid($pid, 0);

    open my $lf, '<', "$dir/logs/error.log" or die "no error log: $!";
    my $log = do { local $/; <$lf> };
    close $lf;

    # the frozen timer was flushed before cleanup and executed as premature
    like($log, qr/premature/, "$name: timer fired with premature flag");

    # D10 invariant: pending_timers counter must not desync
    unlike($log, qr/counter got out of sync/,
           "$name: timer counter in sync");
}

run_one('stalled-remote-read', 'on');
run_signal('sigterm-during-yield', 'TERM');
run_frozen_timer_signal('sigterm-with-frozen-timer', 'TERM');

done_testing();
