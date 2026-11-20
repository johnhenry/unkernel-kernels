#!/usr/bin/env bash
# Static arm64 (glibc) nft and iptables-legacy, built INSIDE the build container, handed into the guest via mounts.
set -euo pipefail
B=https://www.netfilter.org/projects
mkdir -p /tmp/nf/prefix && cd /tmp/nf
get() { curl -fsSL -o "$1" "$B/$2/files/$1"; sha256sum "$1" | tee -a /out/netfilter-tools.sha256; tar xf "$1"; }
: > /out/netfilter-tools.sha256
get libmnl-1.0.5.tar.bz2 libmnl; get libnftnl-1.3.2.tar.xz libnftnl; get nftables-1.1.7.tar.xz nftables; get iptables-1.8.13.tar.xz iptables
P=/tmp/nf/prefix
export PKG_CONFIG_PATH=$P/lib/pkgconfig
(cd libmnl-1.0.5 && ./configure --prefix=$P --enable-static --disable-shared >/dev/null && make -j8 >/dev/null && make install >/dev/null)
(cd libnftnl-1.3.2 && ./configure --prefix=$P --enable-static --disable-shared >/dev/null && make -j8 >/dev/null && make install >/dev/null)
(cd nftables-1.1.7 && ./configure --prefix=$P --disable-shared --enable-static --with-mini-gmp --without-cli --disable-python --disable-man-doc --disable-debug LDFLAGS=-static >/dev/null && make -j8 LDFLAGS="-all-static" >/dev/null && cp src/nft /out/nft-static-arm64)
(cd iptables-1.8.13 && ./configure --prefix=$P --enable-static --disable-shared --disable-nftables --disable-ipv6 --disable-connlabel LDFLAGS=-static >/dev/null && make -j8 LDFLAGS="-all-static" >/dev/null && cp iptables/xtables-legacy-multi /out/xtables-legacy-multi-arm64)
file /out/nft-static-arm64 /out/xtables-legacy-multi-arm64; ls -l /out/nft-static-arm64 /out/xtables-legacy-multi-arm64
