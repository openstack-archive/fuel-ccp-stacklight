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
for a in snap snap-plugins; do
	f="${a}-${RELEASE}-${PLATFORM}-${ARCH}.tar.gz"
	curl -s -k -L -o $TDIR/$f https://bintray.com/olivierbourdon38/Snap/download_file?file_path=$f
	tar zxCf $TDIR $TDIR/$f
done

rsync -a --exclude='*mock[12]' $TDIR/snap-${RELEASE}/bin/ $TDIR/snap-${RELEASE}/plugin/ /usr/local/bin
for f in /usr/local/bin/snap-plugin*; do
	ln -s $f $AUTO_DISCOVERY_PATH
done
for f in snap-plugin-collector-processes snap-plugin-collector-smart; do
	if [ -e /usr/local/bin/$f ]; then
		chmod u+s /usr/local/bin/$f
	fi
done

#
# Clean up
#
apt-get purge -y --auto-remove $BUILD_DEPS
apt-get clean
rm -rf /var/lib/apt/lists/*
rm -rf $TDIR

exit 0
