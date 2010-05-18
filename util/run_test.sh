#!/bin/bash
script_dir=$(dirname $0)
root=$(readlink -f $script_dir/..)
export PATH=$root/work/sbin:$PATH
killall nginx
prove -I$root/t/test-nginx/lib $root/t/*.t

