#!/usr/bin/env bash
# Builds a static arm64 (glibc) iproute2 `ip` (+ `bridge`) INSIDE the build container, for hand-in to the guest via mounts.
# Usage (host): docker run --rm -v $PWD/build:/kb:ro -v $PWD/out:/out dib-kernel-build:1 /kb/guest-tools/build-iproute2.sh
set -euo pipefail
V=7.3.0
mkdir -p /tmp/ip && cd /tmp/ip
curl -fsSL -o ip.tar.xz https://mirrors.edge.kernel.org/pub/linux/utils/net/iproute2/iproute2-$V.tar.xz
sha256sum ip.tar.xz | tee /out/iproute2-$V.tar.xz.sha256
tar xf ip.tar.xz && cd iproute2-$V
perl /kb/guest-tools/iproute2-static-linkutil.pl < ip/iplink.c > /tmp/iplink.c.new && cp /tmp/iplink.c.new ip/iplink.c
./configure >/dev/null 2>&1 || true
sed -i 's/^HAVE_ELF:=.*/HAVE_ELF:=n/;s/^HAVE_MNL:=.*/HAVE_MNL:=n/;s/^HAVE_SELINUX:=.*/HAVE_SELINUX:=n/' config.mk || true

sed -i '/ELF\|ZSTD\|ZLIB\|MNL\|elf/d' config.mk
echo 'CFLAGS += -static' >> config.mk
make -j8 LDFLAGS=-static SUBDIRS="lib ip bridge" 2>&1 | tail -5
file ip/ip bridge/bridge
cp ip/ip /out/ip-static-arm64; cp bridge/bridge /out/bridge-static-arm64
ls -l /out/ip-static-arm64 /out/bridge-static-arm64
