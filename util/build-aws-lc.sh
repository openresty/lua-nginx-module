#!/usr/bin/env bash

# this script is for developers only.
# to build nginx with aws-lc, need two patches:
# https://mailman.nginx.org/pipermail/nginx-devel/2024-February/3J4C2B5L67YSKARKNVLLQHHR7QXXMMRI.html
# https://mailman.nginx.org/pipermail/nginx-devel/2024-February/R2AD2Q4XEVNAYEZY6WEVQBAKTM45OMTG.html
# those patches are merged into nginx-*-aws-lc.patch

root=`pwd`

tar -xzf aws-lc.tar.gz
mv aws-lc-* aws-lc
cmake $root/aws-lc -GNinja -B$root/aws-lc-build -DCMAKE_INSTALL_PREFIX=/opt/ssl -DBUILD_TESTING=OFF -DDISABLE_GO=ON -DBUILD_TOOL=OFF -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=0
ninja -C $root/aws-lc-build install
