#!/usr/bin/env bash
# Build and test script for lua-nginx-module (based on .travis.yml)
# Usage: bash util/build-and-test.sh [nginx_version] [--skip-deps] [--skip-build] [--http2] [--http3]
#
# Options:
#   nginx_version     NGINX version to build (default: 1.29.4)
#   --skip-deps       Skip cloning/updating dependencies
#   --skip-build      Skip build steps, only run tests
#   --http2           Enable HTTP/2 testing (TEST_NGINX_USE_HTTP2=1)
#   --http3           Enable HTTP/3 testing (TEST_NGINX_USE_HTTP3=1)
#   --boring          Use BoringSSL instead of OpenSSL

set -e

# ── Parse arguments ────────────────────────────────────────────────────────────
NGINX_VERSION=1.29.4
SKIP_DEPS=0
SKIP_BUILD=0
USE_HTTP2=0
USE_HTTP3=0
USE_BORINGSSL=0

for arg in "$@"; do
    case "$arg" in
        --skip-deps)   SKIP_DEPS=1 ;;
        --skip-build)  SKIP_BUILD=1 ;;
        --http2)       USE_HTTP2=1 ;;
        --http3)       USE_HTTP3=1 ;;
        --boring)      USE_BORINGSSL=1 ;;
        [0-9]*)        NGINX_VERSION="$arg" ;;
        *)             echo "Unknown option: $arg"; exit 1 ;;
    esac
done

# ── Global environment variables ───────────────────────────────────────────────
export JOBS=${JOBS:-$(nproc)}
export NGX_BUILD_JOBS=$JOBS
export CC=${CC:-gcc}
export NGX_BUILD_CC=$CC

export PCRE2_PREFIX=/usr/local/openresty/pcre2
export PCRE2_LIB=$PCRE2_PREFIX/lib
export PCRE2_INC=$PCRE2_PREFIX/include

export OPENSSL_PREFIX=/usr/local/openresty/openssl3
export OPENSSL_LIB=$OPENSSL_PREFIX/lib
export OPENSSL_INC=$OPENSSL_PREFIX/include

export DRIZZLE_VER=2011.07.21
export BORINGSSL_RELEASE=v20230902
export BORINGSSL_BUILD=20230902

ARCH_RAW="$(uname -m)"
case "$ARCH_RAW" in
    x86_64|amd64) BORINGSSL_ARCH=x64 ;;
    *)            BORINGSSL_ARCH="$ARCH_RAW" ;;
esac

if command -v lsb_release >/dev/null 2>&1; then
    DIST_CODENAME="$(lsb_release -sc)"
elif [ -r /etc/os-release ]; then
    DIST_CODENAME="$(. /etc/os-release && echo "${VERSION_CODENAME:-}")"
fi
DIST_CODENAME="${DIST_CODENAME:-focal}"

export TEST_NGINX_SLEEP=0.006
export TEST_NGINX_SKIP_COSOCKET_LOG_TEST=1
export MALLOC_PERTURB_=9
export TEST_NGINX_TIMEOUT=${TEST_NGINX_TIMEOUT:-5}
export TEST_NGINX_RESOLVER=8.8.4.4

if [ $USE_HTTP2 -eq 1 ]; then
    export TEST_NGINX_USE_HTTP2=1
fi

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILDROOT="$ROOT/buildroot"
DOWNLOAD_ROOT="$BUILDROOT/downloads"
DEPS_ROOT="$BUILDROOT/deps"
DOWNLOAD_CACHE="$DOWNLOAD_ROOT/cache"
MODULES_ROOT="$DOWNLOAD_ROOT/modules"
TEST_NGINX_ROOT="$DOWNLOAD_ROOT/test-nginx"
OPENRESTY_UTILS_ROOT="$DOWNLOAD_ROOT/openresty-devel-utils"
MOCKEAGAIN_ROOT="$DOWNLOAD_ROOT/mockeagain"
LUA_CJSON_ROOT="$DOWNLOAD_ROOT/lua-cjson"
LUAJIT_SRC_ROOT="$DOWNLOAD_ROOT/luajit2"
DRIZZLE_SRC_ROOT="$DOWNLOAD_ROOT/drizzle-src"
BORINGSSL_TARBALL=""

# LuaJIT and drizzle install into buildroot-local deps/ (no sudo needed)
export LUAJIT_PREFIX="$DEPS_ROOT/luajit21"
export LUAJIT_LIB=$LUAJIT_PREFIX/lib
export LUAJIT_INC="$LUAJIT_PREFIX/include/luajit-2.0"
export LUA_INCLUDE_DIR=$LUAJIT_INC

export LIBDRIZZLE_PREFIX="$DEPS_ROOT/drizzle"
export LIBDRIZZLE_INC=$LIBDRIZZLE_PREFIX/include/libdrizzle-1.0
export LIBDRIZZLE_LIB=$LIBDRIZZLE_PREFIX/lib

export LD_LIBRARY_PATH=$LUAJIT_LIB:$LD_LIBRARY_PATH

mkdir -p \
    "$DOWNLOAD_CACHE" \
    "$MODULES_ROOT" \
    "$DEPS_ROOT" \
    "$DRIZZLE_SRC_ROOT"

log() { echo "==> $*"; }
run_logged() {
    "$@" > build.log 2>&1 || { echo "FAILED: $*"; cat build.log; exit 1; }
}

set_luajit_include_dir() {
    local candidates=(
        "$LUAJIT_PREFIX/include/luajit-2.1"
        "$LUAJIT_PREFIX/include/luajit-2.0"
        "$LUAJIT_PREFIX/include"
    )
    local candidate
    for candidate in "${candidates[@]}"; do
        if [ -f "$candidate/luajit.h" ]; then
            export LUAJIT_INC="$candidate"
            export LUA_INCLUDE_DIR="$candidate"
            return
        fi
    done
}

clean_ngx_buildroot() {
    if [ -d "$BUILDROOT" ]; then
        find "$BUILDROOT" -mindepth 1 -maxdepth 1 \
            ! -name downloads \
            ! -name deps \
            -exec rm -rf {} +
    fi
}

# ── Step 1: System package dependencies ───────────────────────────────────────
install_sys_deps() {
    log "Installing system packages..."
    sudo apt-get update -q
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        ack axel cpanminus \
        libtest-base-perl libtext-diff-perl liburi-perl libwww-perl \
        libtest-longstring-perl liblist-moreutils-perl \
        libgd-dev time cmake libunwind-dev wget \
        libbrotli1 lsb-release gnupg ca-certificates \
        mysql-server redis-server memcached gcc make

    # Install OpenResty apt repo for PCRE2 and OpenSSL3
    if ! dpkg -l openresty-pcre2 &>/dev/null; then
        wget -qO - https://openresty.org/package/pubkey.gpg | sudo apt-key add -
        echo "deb http://openresty.org/package/ubuntu $(lsb_release -sc) main" \
            | sudo tee /etc/apt/sources.list.d/openresty.list
        sudo apt-get update -q
        sudo DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
            openresty-pcre2 openresty-openssl3 \
            openresty-pcre2-dev openresty-openssl3-dev
    fi

    log "Installing Perl test modules..."
    /usr/bin/env perl "$(command -v cpanm)" --sudo --notest Test::Nginx IPC::Run
}

# ── Step 2: Clone / update dependency repos ────────────────────────────────────
clone_or_update() {
    local url="$1" dest="$2"
    local branch="${3:-}"
    if [ -d "$dest/.git" ]; then
        log "Updating $(basename "$dest")..."
        git -C "$dest" pull --quiet
    else
        log "Cloning $(basename "$dest")..."
        if [ -n "$branch" ]; then
            git clone -b "$branch" --depth=1 "$url" "$dest"
        else
            git clone --depth=1 "$url" "$dest"
        fi
    fi
}

install_deps() {
    log "Cloning dependency repositories..."
    cd "$ROOT"

    clone_or_update https://github.com/openresty/test-nginx.git            "$TEST_NGINX_ROOT"
    clone_or_update https://github.com/openresty/openresty.git             "$MODULES_ROOT/openresty"
    clone_or_update https://github.com/openresty/no-pool-nginx.git         "$MODULES_ROOT/no-pool-nginx"
    clone_or_update https://github.com/openresty/openresty-devel-utils.git "$OPENRESTY_UTILS_ROOT"
    clone_or_update https://github.com/openresty/mockeagain.git            "$MOCKEAGAIN_ROOT"
    clone_or_update https://github.com/openresty/lua-cjson.git             "$LUA_CJSON_ROOT"
    clone_or_update https://github.com/openresty/lua-upstream-nginx-module.git "$MODULES_ROOT/lua-upstream-nginx-module"
    clone_or_update https://github.com/openresty/echo-nginx-module.git          "$MODULES_ROOT/echo-nginx-module"
    clone_or_update https://github.com/openresty/nginx-eval-module.git          "$MODULES_ROOT/nginx-eval-module"
    clone_or_update https://github.com/simpl/ngx_devel_kit.git                  "$MODULES_ROOT/ndk-nginx-module"
    clone_or_update https://github.com/FRiCKLE/ngx_coolkit.git                  "$MODULES_ROOT/coolkit-nginx-module"
    clone_or_update https://github.com/openresty/headers-more-nginx-module.git  "$MODULES_ROOT/headers-more-nginx-module"
    clone_or_update https://github.com/openresty/drizzle-nginx-module.git       "$MODULES_ROOT/drizzle-nginx-module"
    clone_or_update https://github.com/openresty/set-misc-nginx-module.git      "$MODULES_ROOT/set-misc-nginx-module"
    clone_or_update https://github.com/openresty/memc-nginx-module.git          "$MODULES_ROOT/memc-nginx-module"
    clone_or_update https://github.com/openresty/rds-json-nginx-module.git      "$MODULES_ROOT/rds-json-nginx-module"
    clone_or_update https://github.com/openresty/srcache-nginx-module.git       "$MODULES_ROOT/srcache-nginx-module"
    clone_or_update https://github.com/openresty/redis2-nginx-module.git        "$MODULES_ROOT/redis2-nginx-module"
    clone_or_update https://github.com/openresty/lua-resty-core.git             "$MODULES_ROOT/lua-resty-core"
    clone_or_update https://github.com/openresty/lua-resty-lrucache.git         "$MODULES_ROOT/lua-resty-lrucache"
    clone_or_update https://github.com/openresty/lua-resty-mysql.git            "$MODULES_ROOT/lua-resty-mysql"
    clone_or_update https://github.com/spacewander/lua-resty-rsa.git            "$MODULES_ROOT/lua-resty-rsa"
    clone_or_update https://github.com/openresty/lua-resty-string.git           "$MODULES_ROOT/lua-resty-string"
    clone_or_update https://github.com/openresty/stream-lua-nginx-module.git    "$MODULES_ROOT/stream-lua-nginx-module"
    clone_or_update https://github.com/openresty/luajit2.git "$LUAJIT_SRC_ROOT" "v2.1-agentzh"

    # Download drizzle prebuilt tarball
    if [ ! -f "$DOWNLOAD_CACHE/drizzle7-$DRIZZLE_VER.tar.gz" ]; then
        log "Downloading drizzle7 $DRIZZLE_VER..."
        wget -q -P "$DOWNLOAD_CACHE" \
            "https://github.com/openresty/openresty-deps-prebuild/releases/download/v20230902/drizzle7-$DRIZZLE_VER.tar.gz"
    fi

    if [ $USE_BORINGSSL -eq 1 ]; then
        local candidates=(
            "boringssl-${BORINGSSL_BUILD}-${BORINGSSL_ARCH}-${DIST_CODENAME}.tar.gz"
            "boringssl-${BORINGSSL_BUILD}-${BORINGSSL_ARCH}-focal.tar.gz"
        )
        local pkg=""
        for candidate in "${candidates[@]}"; do
            if [ -f "$DOWNLOAD_CACHE/$candidate" ]; then
                pkg="$candidate"
                break
            fi
        done

        if [ -z "$pkg" ]; then
            log "Downloading BoringSSL prebuilt (arch=$BORINGSSL_ARCH, distro=$DIST_CODENAME)..."
            for candidate in "${candidates[@]}"; do
                if wget -q -P "$DOWNLOAD_CACHE" \
                    "https://github.com/openresty/openresty-deps-prebuild/releases/download/$BORINGSSL_RELEASE/$candidate"
                then
                    pkg="$candidate"
                    break
                fi
            done
        fi

        if [ -n "$pkg" ]; then
            BORINGSSL_TARBALL="$DOWNLOAD_CACHE/$pkg"
            log "Using BoringSSL package: $pkg"
        fi
    fi
}

# ── Step 3: Build LuaJIT ──────────────────────────────────────────────────────
build_luajit() {
    log "Building LuaJIT..."
    cd "$LUAJIT_SRC_ROOT"
    run_logged make -j"$JOBS" CCDEBUG=-g Q= PREFIX="$LUAJIT_PREFIX" CC="$CC" \
        XCFLAGS='-DLUA_USE_APICHECK -DLUA_USE_ASSERT -msse4.2'
    run_logged make install PREFIX="$LUAJIT_PREFIX"
    set_luajit_include_dir
    cd "$ROOT"
}

# ── Step 4: Build drizzle ─────────────────────────────────────────────────────
build_drizzle() {
    log "Building drizzle7..."
    cd "$DRIZZLE_SRC_ROOT"
    rm -rf "drizzle7-$DRIZZLE_VER"
    tar xzf "$DOWNLOAD_CACHE/drizzle7-$DRIZZLE_VER.tar.gz"
    cd "$DRIZZLE_SRC_ROOT/drizzle7-$DRIZZLE_VER"
    run_logged ./configure --prefix="$LIBDRIZZLE_PREFIX" --without-server
    run_logged make libdrizzle-1.0 -j"$JOBS"
    run_logged make install-libdrizzle-1.0
    cd "$ROOT"
    rm -rf "$DRIZZLE_SRC_ROOT/drizzle7-$DRIZZLE_VER"
}

# ── Step 5: Build mockeagain ──────────────────────────────────────────────────
build_mockeagain() {
    log "Building mockeagain..."
    cd "$MOCKEAGAIN_ROOT"
    run_logged make CC="$CC" -j"$JOBS"
    cd "$ROOT"
}

# ── Step 6: Build lua-cjson ───────────────────────────────────────────────────
build_lua_cjson() {
    log "Building lua-cjson..."
    cd "$LUA_CJSON_ROOT"
    # Install cjson.so alongside LuaJIT's own Lua C modules (no sudo needed)
    local cmod_dir="$LUAJIT_PREFIX/lib/lua/5.1"
    mkdir -p "$cmod_dir"
    run_logged make -j"$JOBS" LUA_CMODULE_DIR="$cmod_dir" LUA_MODULE_DIR="$cmod_dir"
    run_logged make install LUA_CMODULE_DIR="$cmod_dir" LUA_MODULE_DIR="$cmod_dir"
    cd "$ROOT"
}

# ── Step 7: Set up BoringSSL (optional) ───────────────────────────────────────
setup_boringssl() {
    if [ $USE_BORINGSSL -eq 1 ]; then
        log "Setting up BoringSSL..."
        # Override OPENSSL_PREFIX to a buildroot-local path (no sudo needed)
        export OPENSSL_PREFIX="$DEPS_ROOT/boringssl"
        export OPENSSL_LIB=$OPENSSL_PREFIX/lib
        export OPENSSL_INC=$OPENSSL_PREFIX/include
        if [ -z "$BORINGSSL_TARBALL" ]; then
            local candidates=(
                "$DOWNLOAD_CACHE/boringssl-${BORINGSSL_BUILD}-${BORINGSSL_ARCH}-${DIST_CODENAME}.tar.gz"
                "$DOWNLOAD_CACHE/boringssl-${BORINGSSL_BUILD}-${BORINGSSL_ARCH}-focal.tar.gz"
            )
            local candidate
            for candidate in "${candidates[@]}"; do
                if [ -f "$candidate" ]; then
                    BORINGSSL_TARBALL="$candidate"
                    break
                fi
            done
        fi

        if [ -z "$BORINGSSL_TARBALL" ] && \
            [ -f "$OPENSSL_INC/openssl/base.h" ] && \
            [ -f "$OPENSSL_LIB/libssl.so" ] && \
            [ -f "$OPENSSL_LIB/libcrypto.so" ]
        then
            log "Reusing existing BoringSSL in $OPENSSL_PREFIX"
            return
        fi

        if [ -z "$BORINGSSL_TARBALL" ] || [ ! -f "$BORINGSSL_TARBALL" ]; then
            echo "ERROR: BoringSSL package not found for arch=$BORINGSSL_ARCH distro=$DIST_CODENAME." >&2
            echo "Tried download-cache and fallback focal package from $BORINGSSL_RELEASE." >&2
            exit 1
        fi

        rm -fr "$OPENSSL_PREFIX"
        mkdir -p "$OPENSSL_PREFIX"
        tar -C "$OPENSSL_PREFIX" -xf "$BORINGSSL_TARBALL" --strip-components=1
    fi
}

# ── Step 8: Build nginx ───────────────────────────────────────────────────────
build_nginx() {
    log "Building nginx $NGINX_VERSION..."
    export MODULES_ROOT
    export PATH="$ROOT/work/nginx/sbin:$OPENRESTY_UTILS_ROOT:$PATH"

    # Run all three build variants (mirrors CI)
    run_logged sh "$ROOT/util/build-without-ssl.sh" "$NGINX_VERSION"
    run_logged sh "$ROOT/util/build-with-dd.sh"     "$NGINX_VERSION"
    clean_ngx_buildroot
    run_logged sh "$ROOT/util/build.sh"              "$NGINX_VERSION"

    log "nginx version:"
    nginx -V

    log "nginx dynamic library links:"
    ldd "$(which nginx)" | grep -E 'luajit|ssl|pcre' || true
}

# ── Step 9: Set up iptables / sysctl (mirrors CI network rules) ──────────────
setup_network() {
    log "Configuring network rules..."
    sudo iptables -I OUTPUT 1 -p udp --dport 10086 -j REJECT             2>/dev/null || true
    sudo iptables -I OUTPUT   -p tcp --dst 127.0.0.2 --dport 12345 -j DROP 2>/dev/null || true
    sudo iptables -I OUTPUT   -p udp --dst 127.0.0.2 --dport 12345 -j DROP 2>/dev/null || true
    sudo ip route add prohibit 0.0.0.1/32 2>/dev/null || true
    sudo sysctl -w kernel.pid_max=10000 2>/dev/null || true
}

# ── Step 10: Set up MySQL ─────────────────────────────────────────────────────
setup_mysql() {
    log "Setting up MySQL test database..."
    mysql -uroot -e "
        CREATE DATABASE IF NOT EXISTS ngx_test;
        CREATE USER IF NOT EXISTS 'ngx_test'@'%' IDENTIFIED WITH mysql_native_password BY 'ngx_test';
        GRANT ALL ON ngx_test.* TO 'ngx_test'@'%';
        FLUSH PRIVILEGES;
    " 2>/dev/null || \
    mysql -uroot --password='' -e "
        CREATE DATABASE IF NOT EXISTS ngx_test;
        CREATE USER IF NOT EXISTS 'ngx_test'@'%' IDENTIFIED BY 'ngx_test';
        GRANT ALL ON ngx_test.* TO 'ngx_test'@'%';
        FLUSH PRIVILEGES;
    " 2>/dev/null || log "WARNING: MySQL setup failed (tests requiring MySQL may fail)"
}

# ── Step 11: Run tests ────────────────────────────────────────────────────────
run_tests() {
    log "Running tests..."
    cd "$ROOT"

    export PATH="$ROOT/work/nginx/sbin:$OPENRESTY_UTILS_ROOT:$PATH"
    export LD_PRELOAD="$MOCKEAGAIN_ROOT/mockeagain.so"
    export LD_LIBRARY_PATH="$MOCKEAGAIN_ROOT:$LD_LIBRARY_PATH"
    export TEST_NGINX_HTTP3_CRT="$ROOT/t/cert/http3/http3.crt"
    export TEST_NGINX_HTTP3_KEY="$ROOT/t/cert/http3/http3.key"

    if [ $USE_HTTP3 -eq 1 ]; then
        export TEST_NGINX_USE_HTTP3=1
        export TEST_NGINX_QUIC_IDLE_TIMEOUT=3
    fi

    # Clean up stale nc_server from previous aborted runs.
    pkill -f "$ROOT/util/nc_server.py" 2>/dev/null || true

    # Start nc_server in background (used by some tests)
    python3 "$ROOT/util/nc_server.py" &
    NC_PID=$!
    trap 'kill "$NC_PID" 2>/dev/null || true' EXIT INT TERM

    # Allow passing specific test files via TEST_NGINX_TARGETS env var
    TARGETS="${TEST_NGINX_TARGETS:-t/}"
    CORE_PERL_LIB="$(perl -MConfig -e 'print $Config{installprivlib}')"
    CORE_PERL_ARCH="$(perl -MConfig -e 'print $Config{archlib}')"

    /usr/bin/env perl "$(command -v prove)" \
        -I"$CORE_PERL_LIB" \
        -I"$CORE_PERL_ARCH" \
        -I. \
        -I"$TEST_NGINX_ROOT/inc" \
        -I"$TEST_NGINX_ROOT/lib" \
        -r $TARGETS

    kill "$NC_PID" 2>/dev/null || true
    trap - EXIT INT TERM
}

# ── Source code style check (mirrors CI before_install) ───────────────────────
check_style() {
    log "Checking source code style..."
    cd "$ROOT"
    if grep -n -P '(?<=.{80}).+' $(find src -name '*.c') $(find . -name '*.h') 2>/dev/null; then
        echo "ERROR: Found C source lines exceeding 80 columns." >&2
        exit 1
    fi
    if grep -n -P '\t+' $(find src -name '*.c') $(find . -name '*.h') 2>/dev/null; then
        echo "ERROR: Cannot use tabs." >&2
        exit 1
    fi
    log "Style check passed."
}

# ── Main ───────────────────────────────────────────────────────────────────────
cd "$ROOT"

if [ $SKIP_BUILD -eq 0 ]; then
    # check_style

    if [ $SKIP_DEPS -eq 0 ]; then
        # install_sys_deps
        install_deps
    fi

    build_luajit
    build_drizzle
    build_mockeagain
    build_lua_cjson
    setup_boringssl
    # setup_network
    # setup_mysql
    build_nginx
fi

run_tests
