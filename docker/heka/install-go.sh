#!/bin/bash

set -e

GOLANG_VERSION="1.6.2"
GOLANG_DOWNLOAD_URL="https://golang.org/dl/go${GOLANG_VERSION}.linux-amd64.tar.gz"
GOLANG_DOWNLOAD_SHA256="e40c36ae71756198478624ed1bb4ce17597b3c19d243f3f0899bb5740d56212a"

curl -fsSL ${GOLANG_DOWNLOAD_URL} -o golang.tar.gz
echo "${GOLANG_DOWNLOAD_SHA256} golang.tar.gz" | sha256sum -c -
tar -C /usr/local -xzf golang.tar.gz
rm golang.tar.gz
