#!/bin/bash

set -e

if [ $# -ne 1 ]; then
	echo "Usage: $0 directory"
	exit 1
fi

if [ ! -d "$1" ]; then
	echo "Error: $1 does not exist or is not a directory"
	exit 1
fi

SRC=/opt/ccp/hindsight
if [ ! -d "$SRC" ]; then
	echo "Error: $SRC does not exist or is not a directory"
	exit 1
fi

# The following command might print errors in its output
# when used with containers shared volumes (like
# can not restore atime ...)
tar cf - -C $SRC . | tar xf - -C $1 --strip-components=1
