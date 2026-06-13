# vim:set ft= ts=4 sw=4 et fdm=marker:
#
# Regression test for openresty/openresty#1131.
# The http2_subreq_error_wakeup patch must not skip request termination for
# native nginx subrequests, such as slice range subrequests, which do not have
# a post_subrequest callback waiting to resume a parent coroutine.
#
# The test warms a sliced proxy cache first.  It then opens a raw h2c client,
# requests the cached sliced file, reads a few slices, and stops reading while
# keeping the connection open.  That makes nginx hit send_timeout while the
# active request is a native slice subrequest.  A buggy build falls through to
# special response handling and logs "header already sent"; a fixed build
# terminates the native subrequest instead.

our $SkipReason;

BEGIN {
    my $nginx = $ENV{TEST_NGINX_BINARY} || 'nginx';
    my $nginx_version = `$nginx -V 2>&1`;

    if ($? != 0) {
        $SkipReason = "failed to get nginx version";

    } elsif ($nginx_version !~ /--with-http_slice_module/) {
        $SkipReason =  "requires nginx built with --with-http_slice_module";
    }
}

use File::Path qw(remove_tree);
use Test::Nginx::Socket::Lua $SkipReason ? (skip_all => $SkipReason)
                                         : ('no_plan');

repeat_each(1);

no_shuffle();
no_long_string();

our $HtmlDir = html_dir;
$ENV{TEST_NGINX_HTML_DIR} = $HtmlDir;

our $ServerRoot = server_root();
our $CacheDir = "$ServerRoot/slice_cache";
remove_tree($CacheDir);
add_cleanup_handler(sub { remove_tree($CacheDir) });

our $HttpConfig = qq{
    proxy_cache_path $CacheDir levels=1:2 keys_zone=slicecache:10m
                     inactive=10m max_size=50m;
    send_timeout 1s;

    upstream slice_origin {
        server unix:$HtmlDir/slice-origin.sock;
    }

    server {
        listen unix:$HtmlDir/slice-origin.sock;

        location / {
            root $HtmlDir;
        }
    }
};

run_tests();

__DATA__

=== TEST 1: stalled HTTP/2 client timeout with cached slice subrequests
--- http_config eval: $::HttpConfig
--- config
    location = /ping {
        return 200 "ok\n";
    }

    location = /slice.bin {
        send_timeout       1s;
        slice              128k;
        proxy_cache        slicecache;
        proxy_cache_key    "$uri $slice_range";
        proxy_set_header   Range $slice_range;
        proxy_cache_valid  200 206 1h;
        proxy_pass         http://slice_origin;
    }
--- init
use IO::Select;
use IO::Socket::INET;

sub h2_frame {
    my ($type, $flags, $sid, $payload) = @_;
    my $len = length $payload;

    # Build one HTTP/2 frame:
    #   9-byte frame header (length, type, flags, stream id) + payload.
    return pack("C3 C C N",
                ($len >> 16) & 0xff,
                ($len >> 8) & 0xff,
                $len & 0xff,
                $type,
                $flags,
                $sid & 0x7fffffff)
           . $payload;
}

sub hpack_headers_for_path {
    my ($path) = @_;

    # Minimal HPACK request header block, equivalent to:
    #   :method: GET
    #   :scheme: http
    #   :path: $path
    #   :authority: localhost
    return "\x82\x86"
           . "\x04" . chr(length $path) . $path
           . "\x01" . "\x09" . "localhost";
}

sub run_stalled_h2_client {
    my ($port, $path) = @_;

    # Speak h2c on a raw TCP socket so the test can stop reading without curl
    # closing the connection or changing the timeout path.
    my $sock = IO::Socket::INET->new(
        PeerAddr => "127.0.0.1",
        PeerPort => $port,
        Proto    => "tcp",
        Timeout  => 5,
    ) or die "failed to connect to nginx: $!";

    $sock->autoflush(1);

    my $initial_window = 1024 * 1024;

    # Start an HTTP/2 cleartext session.  The larger stream and connection
    # windows let nginx send several 128k slices before the client stalls.
    print $sock "PRI * HTTP/2.0\r\n\r\nSM\r\n\r\n";
    print $sock h2_frame(0x4, 0x0, 0, pack("nN", 0x4, $initial_window));
    print $sock h2_frame(0x8, 0x0, 0, pack("N", $initial_window));

    # Send a GET request on stream 1.  END_HEADERS | END_STREAM means the
    # request has no body.
    print $sock h2_frame(0x1, 0x5, 1, hpack_headers_for_path($path));

    my $sel = IO::Select->new($sock);
    my $deadline = time + 5;
    my $read = 0;

    # Read about three 128k slices first.  This proves the response is already
    # flowing and makes the later timeout happen during slice subrequest output.
    while ($read < 384 * 1024 && time < $deadline) {
        my @ready = $sel->can_read(0.2);
        next unless @ready;

        my $n = sysread($sock, my $buf, 65536);
        last unless $n;
        $read += $n;
    }

    # Without this precondition, the timeout might hit a different request
    # state and the regression signal would be ambiguous.
    die "stalled HTTP/2 client did not receive enough response bytes: $read"
        if $read < 384 * 1024;

    # Stop reading for longer than send_timeout (1s) while the connection stays
    # open.  This is the actual stalled-client trigger.
    select undef, undef, undef, 2.5;
    close $sock;
}

# Create a multi-slice origin file and warm proxy_cache with a normal client.
# The stalled h2c request below then runs from cached slice subrequests, making
# the timeout path independent of upstream timing.
my $file = "$::HtmlDir/slice.bin";
system("dd", "if=/dev/urandom", "of=$file", "bs=1M", "count=2", "status=none") == 0
    or die "failed to create $file";

my $port = $Test::Nginx::Util::ServerPortForClient;
my $cmd = "curl -sS --connect-timeout 5 --max-time 30 "
          . "http://127.0.0.1:$port/slice.bin -o /dev/null";
system($cmd) == 0 or die "failed to warm sliced proxy cache: $cmd";

run_stalled_h2_client($port, "/slice.bin");
--- http2
--- request
GET /ping
--- response_body
ok
--- error_log
http slice subrequest
client timed out
--- no_error_log
header already sent
[alert]
[crit]
[emerg]
--- no_shutdown_error_log
header already sent
[alert]
[crit]
[emerg]
