#!/bin/bash

set -e

#
# Install build dependencies
#

BUILD_DEPS="git g++ make libssl-dev"
apt-get update
apt-get install -y --no-install-recommends $BUILD_DEPS

#
# Install cmake 3.5.2
# cmake 3.0.2, shipped by Debian Jessie, does not work for building the ssl
# sandbox extension.
# See https://github.com/mozilla-services/lua_sandbox_extensions/issues/19.
#

curl https://cmake.org/files/v3.5/cmake-3.5.2-Linux-x86_64.tar.gz | tar xz -C /tmp
export PATH=/tmp/cmake-3.5.2-Linux-x86_64/bin:$PATH

#
# Build and install lua_sandbox
#

cd /tmp
git clone https://github.com/mozilla-services/lua_sandbox
cd lua_sandbox
git checkout v1.0.3
mkdir release
cd release
cmake -DCMAKE_BUILD_TYPE=release ..
make
make install

#
# Build and install the necessary lua_sandbox extensions
#

cd /tmp
git clone https://github.com/mozilla-services/lua_sandbox_extensions
cd lua_sandbox_extensions
# last tested commit
# https://github.com/mozilla-services/lua_sandbox_extensions/commit/98065e7627ebf7440363ad73024968b01a1d5c53
git checkout 98065e7627ebf7440363ad73024968b01a1d5c53
mkdir release
cd release
cmake -DCMAKE_BUILD_TYPE=release -DEXT_cjson=on -DEXT_heka=on -DEXT_lpeg=on -DEXT_socket=on -DEXT_ssl=on ..
make
# make install does not work
make packages
tar --strip-components=1 -C / -xvzf luasandbox-cjson-*-Linux.tar.gz
tar --strip-components=1 -C / -xvzf luasandbox-heka-*-Linux.tar.gz
tar --strip-components=1 -C / -xvzf luasandbox-lpeg-*-Linux.tar.gz
tar --strip-components=1 -C / -xvzf luasandbox-socket-*-Linux.tar.gz
tar --strip-components=1 -C / -xvzf luasandbox-ssl-*-Linux.tar.gz

ldconfig

#
# Build Hindsight
#

cd /tmp
git clone https://github.com/trink/hindsight
cd hindsight
# last tested commit
# https://github.com/trink/hindsight/commit/d3b257a3eda7c3874e7cf9ac6f095bbb752a1026
git checkout d3b257a3eda7c3874e7cf9ac6f095bbb752a1026
mkdir release
cd release
cmake -DCMAKE_BUILD_TYPE=release ..
make
make install

#
# Create Hindsight dirs and copy lua_sandbox and Hindsight plugins
# into Hindsight's "run" directory
#

mkdir -p \
 /etc/hindsight \
 /var/lib/hindsight/output \
 /var/lib/hindsight/load/analysis \
 /var/lib/hindsight/load/input \
 /var/lib/hindsight/load/output \
 /var/lib/hindsight/run/analysis \
 /var/lib/hindsight/run/input \
 /var/lib/hindsight/run/output

cp /tmp/lua_sandbox_extensions/release/install/share/luasandbox/sandboxes/heka/input/heka_tcp.lua /var/lib/hindsight/run/input/
cp /tmp/hindsight/sandboxes/input/prune_input.lua /var/lib/hindsight/run/input/

#
# Remove build directories
#
rm -rf /tmp/lua_sandbox /tmp/lua_sandbox_extensions /tmp/hindsight /tmp/cmake*
apt-get purge -y --auto-remove $BUILD_DEPS
apt-get clean
rm -rf /var/lib/apt/lists/*

exit 0
