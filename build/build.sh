#!/usr/bin/env bash
# Host driver: reproduces a kernel variant inside Docker. Nothing from the network is executed on the host.
#   build/build.sh [stock|net|netfilter] [--foreground]
# Output: out/unkernel-<variant>-<commit>.wasm (+ .sha256, config-*, toolchain-versions.txt)
# Build tree: named volume dib-kbuild (delete: docker volume rm dib-kbuild).
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
PROJ="$(dirname "$HERE")"
OUT="$PROJ/out"
VARIANT="${1:-stock}"; FG="${2:-}"
IMG=dib-kernel-build:1; VOL=dib-kbuild; NAME="dib-build-$VARIANT"
mkdir -p "$OUT"
docker image inspect "$IMG" >/dev/null 2>&1 || docker build -t "$IMG" "$HERE"
docker volume create "$VOL" >/dev/null
if docker ps -q --filter name=dib-build- | grep -q .; then echo "a build is already running" >&2; exit 1; fi
docker rm -f "$NAME" >/dev/null 2>&1 || true
# Only kernel-build/ (ro), the output dir and the named volume are mounted. No credentials, not privileged.
args=(--name "$NAME" -v "$VOL:/work" -v "$HERE:/kb:ro" -v "$OUT:/out" "$IMG" bash -c "/kb/in-container.sh $VARIANT 2>&1 | tee /out/build-$VARIANT.log")
if [ "$FG" = --foreground ]; then docker run --rm "${args[@]}"; else docker run -d "${args[@]}"; echo "started $NAME; tail -f $OUT/build-$VARIANT.log"; fi
