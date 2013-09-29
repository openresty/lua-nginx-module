use Test::Nginx::Socket -Base;

my $code = $ENV{TEST_NGINX_INIT_BY_LUA};

if ($code) {
    $code =~ s/\\/\\\\/g;
    $code =~ s/['"]/\\$&/g;

    Test::Nginx::Socket::set_http_config_filter(sub {
        my $config = shift;
        if ($config =~ /init_by_lua_file/) {
            return $config;
        }
        unless ($config =~ s{init_by_lua\s*(['"])((?:\\.|.)*)\1\s*;}{init_by_lua $1$code$2$1;}s) {
            $config .= "init_by_lua '$code';";
        }
        return $config;
    });
}

1;
