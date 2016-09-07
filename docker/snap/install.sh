#!/bin/bash

set -e

AUTO_DISCOVERY_PATH="$1"

#
# Install Snap and Snap plugins
#

RELEASE=v0.15.0-beta-98-g0b228f5
PLATFORM=linux
ARCH=amd64
TDIR=/tmp/snap

mkdir -p $TDIR
# Retrieve archived binaries and extract them in temporary location
for a in snap snap-plugins; do
    f="${a}-${RELEASE}-${PLATFORM}-${ARCH}.tar.gz"
    # -L required due to potential successive redirections
    curl -s -k -L -o $TDIR/$f https://bintray.com/olivierbourdon38/Snap/download_file?file_path=$f
    tar zxCf $TDIR $TDIR/$f --exclude '*mock[12]'
done

# Copy retrieved binaries excluding demo plugins
install --owner=root --group=root --mode=755 $TDIR/snap-${RELEASE}/bin/* $TDIR/snap-${RELEASE}/plugin/* /usr/local/bin
# Make the plugins auto-loadable by the snap framework
for f in /usr/local/bin/snap-plugin*; do
    ln -s $f $AUTO_DISCOVERY_PATH
done

# Update some permissions for plugins which require privileged access to filesystem
#
# the processes snap plugin accesses files like /proc/1/io which
# only the root user can read
#
# the smart snap plugin accesses files in /host-proc and /host-dev (/proc and /dev
# from the host) which also requires root user access
#
for f in snap-plugin-collector-processes snap-plugin-collector-smart; do
    chmod u+s /usr/local/bin/$f
done

#
# Clean up
#
apt-get purge -y --auto-remove $BUILD_DEPS
apt-get clean
rm -rf /var/lib/apt/lists/*
rm -rf $TDIR

exit 0
