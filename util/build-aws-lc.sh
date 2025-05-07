#!/usr/bin/env bash

# this script is for developers only.

root=`pwd`

tar -xzf aws-lc.tar.gz
mv aws-lc-* aws-lc
cmake $root/aws-lc -GNinja -B$root/aws-lc-build -DCMAKE_INSTALL_PREFIX=/opt/ssl -DBUILD_TESTING=OFF -DDISABLE_GO=ON -DBUILD_TOOL=OFF -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=0
ninja -C $root/aws-lc-build install
