#!/usr/bin/env bash
# Runs INSIDE the build container (see build.sh). Usage: in-container.sh <stock|net|netfilter>
# Build tree lives in the named volume mounted at /work; artifacts go to /out.
set -euo pipefail
VARIANT="${1:?variant}"
KB=/kb                                   # kernel-build/ mounted read-only
PIN=040e142cd016da066ac018de60fcdcec3201fd24   # tag v0.2.0-261119-040e142
REPO=https://github.com/pithings/unkernel.git
SRC=/work/unkernel
JOBS="${JOBS:-$(nproc)}"
export JOBS
log() { printf '\n=== [%s] %s\n' "$(date -u +%H:%M:%S)" "$*"; }

log "toolchain versions"
{ clang --version | head -1; ld.lld --version; zig version; node -v; cmake --version | head -1; ninja --version
  gcc --version | head -1; mke2fs -V 2>&1 | head -1 || true; } | tee /out/toolchain-versions.txt

if [ ! -d "$SRC/.git" ]; then
  log "clone upstream"
  mkdir -p "$SRC" && cd "$SRC" && git init -q && git remote add origin "$REPO"
  git fetch --depth 1 origin "$PIN"
  git checkout -q --detach FETCH_HEAD
fi
cd "$SRC"
[ "$(git rev-parse HEAD)" = "$PIN" ] || { echo "upstream HEAD is not $PIN" >&2; exit 1; }
echo "upstream commit: $(git rev-parse HEAD)"

# Hook for extra config fragments (see patches/0001-build-extra-frags.patch); idempotent.
if ! grep -q KW_EXTRA_FRAGS kernel/build.sh; then
  perl -0pi -e 's/(\t\tfrags\+=\(kw_smp\.config\)\n\tfi\n)/$1\t# dib: extra fragments for both kernels (KW_EXTRA_FRAGS)\n\tfrags+=(\${KW_EXTRA_FRAGS:-})\n/' kernel/build.sh
  grep -q 'frags+=(${KW_EXTRA_FRAGS' kernel/build.sh
  git diff kernel/build.sh > /out/0001-build-extra-frags.patch
fi

log "setup.sh --check"
./setup.sh --check

if [ ! -f zig-out/lib/libkwemu.a ]; then
  log "zig build kwemu (UP) + kwemu-smp"
  zig build -Dkwemu-jit=true -Dcpu=baseline
  zig build -Dkwemu-jit=true -Dkwemu-atomics=true -Dcpu=baseline --prefix vendor/build/kwemu-smp
fi
export KWEMU="$SRC/zig-out/lib/libkwemu.a" KWEMU_SMP="$SRC/vendor/build/kwemu-smp/lib/libkwemu.a"
export KW_RELEASE=1 KW_SMP=1

case "$VARIANT" in
  stock)
    export KW_BUILD=$SRC/vendor/build ;;   # default tree
  net|netfilter)
    export KW_BUILD=/work/out-$VARIANT KSRC=/work/ksrc-$VARIANT
    if [ ! -e "$KSRC/.git" ]; then
      log "prepare kernel tree $KSRC"
      git -C "$SRC/vendor/src/linux-wasm-kernel" worktree add -q -b "dib-$VARIANT" "$KSRC" kw-arm64-user
      for p in "$KB"/patches/linux/*.patch; do
        [ -e "$p" ] || continue
        git -C "$KSRC" -c user.name=dib -c user.email=dib@localhost am "$p"
      done
      cp "$KB/fragments/net.config" "$KSRC/arch/wasm/configs/net.config"
      [ "$VARIANT" = netfilter ] && cp "$KB/fragments/netfilter.config" "$KSRC/arch/wasm/configs/netfilter.config"
      git -C "$KSRC" add arch/wasm/configs
      git -C "$KSRC" -c user.name=dib -c user.email=dib@localhost commit -q -m "dib: $VARIANT config fragments"
    fi
    export KW_EXTRA_FRAGS="net.config"
    [ "$VARIANT" = netfilter ] && export KW_EXTRA_FRAGS="net.config netfilter.config" ;;
  *) echo "unknown variant $VARIANT" >&2; exit 2 ;;
esac

log "kernel/build.sh kernel (UP)";  kernel/build.sh kernel
log "kernel/build.sh smp";          kernel/build.sh smp
log "kernel/build.sh datadisk";     kernel/build.sh datadisk
log "kernel/build.sh base";         KW_BASE_OUT= kernel/build.sh base

OUT_WASM="$KW_BUILD/bundle/unkernel.wasm"
ls -l "$OUT_WASM"
cp "$OUT_WASM" "/out/unkernel-$VARIANT-${PIN:0:7}.wasm"
for k in kernel kernel-smp; do
  [ -f "$KW_BUILD/$k/.config" ] && cp "$KW_BUILD/$k/.config" "/out/config-$VARIANT-$k"
done
( cd /out && sha256sum "unkernel-$VARIANT-${PIN:0:7}.wasm" | tee "unkernel-$VARIANT-${PIN:0:7}.wasm.sha256" )
log "DONE $VARIANT"
