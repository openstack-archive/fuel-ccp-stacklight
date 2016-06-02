#!/bin/bash

set -e

PLUGINDIR="$1"
export GOPATH="/go"

mkdir -p "$GOPATH/src" "$GOPATH/bin"
chmod -R 777 "$GOPATH"

export PATH=/usr/local/go/bin:$GOPATH/bin/:$PATH

echo "Get system dependencies..."
BUILD_DEPS="git gcc g++ libc6-dev make cmake debhelper fakeroot patch"
apt-get update
apt-get install -y --no-install-recommends $BUILD_DEPS

echo "Get and build Heka..."
cd /tmp
git clone -b dev --single-branch https://github.com/mozilla-services/heka
cd heka
source build.sh  # changes GOPATH to /tmp/heka/build/heka and builds Heka
install -vD /tmp/heka/build/heka/bin/* /usr/local/bin/
cp -rp /tmp/heka/build/heka/lib/lib* /usr/lib/
cp -rp /tmp/heka/build/heka/lib/luasandbox/modules/* /usr/share/heka/lua_modules/

echo "Clean up..."
apt-get purge -y --auto-remove $BUILD_DEPS
apt-get clean
rm -rf /tmp/heka
rm -rf /var/lib/apt/lists/*
rm -rf $GOPATH
