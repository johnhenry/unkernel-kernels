# Build environment for the unkernel (Linux-on-WebAssembly) kernels.
# linux/arm64 (native on Apple Silicon Docker Desktop). Mirrors upstream's
# release workflow: clang 22 + lld/llvm 22 (apt.llvm.org), Zig 0.16.0, Node 24,
# cmake, ninja, flex, bison, bc, m4, e2fsprogs, patch, perl.
FROM debian:trixie

ARG ZIG_VERSION=0.16.0
ARG ZIG_SHA256=ea4b09bfb22ec6f6c6ceac57ab63efb6b46e17ab08d21f69f3a48b38e1534f17
ARG NODE_VERSION=24.22.3
ARG NODE_SHA256=6e51a2ada00f0011cc266f65d98922b403d7ad88f809ca2aa615a5fe1ce6e86c
ARG LLVM_MAJOR=22

ENV DEBIAN_FRONTEND=noninteractive LANG=C.UTF-8
RUN apt-get update -q && apt-get install -y -q --no-install-recommends \
      ca-certificates curl gnupg xz-utils git build-essential cmake ninja-build \
      flex bison bc m4 e2fsprogs patch perl python3 libssl-dev libelf-dev \
      cpio gzip bzip2 zstd unzip file rsync kmod \
      autoconf automake libtool pkg-config liblz4-dev libzstd-dev uuid-dev \
      zlib1g-dev jq \
 && install -d -m 0755 /etc/apt/keyrings \
 && curl -fsSL https://apt.llvm.org/llvm-snapshot.gpg.key -o /etc/apt/keyrings/apt.llvm.org.asc \
 && echo "deb [signed-by=/etc/apt/keyrings/apt.llvm.org.asc] http://apt.llvm.org/trixie/ llvm-toolchain-trixie-${LLVM_MAJOR} main" \
      > /etc/apt/sources.list.d/llvm.list \
 && apt-get update -q && apt-get install -y -q --no-install-recommends \
      clang-${LLVM_MAJOR} lld-${LLVM_MAJOR} llvm-${LLVM_MAJOR} \
 && rm -rf /var/lib/apt/lists/*

RUN curl -fsSL -o /tmp/zig.tar.xz https://ziglang.org/download/${ZIG_VERSION}/zig-aarch64-linux-${ZIG_VERSION}.tar.xz \
 && echo "${ZIG_SHA256}  /tmp/zig.tar.xz" | sha256sum -c - \
 && mkdir -p /opt/zig && tar -xJf /tmp/zig.tar.xz -C /opt/zig --strip-components=1 && rm /tmp/zig.tar.xz \
 && ln -s /opt/zig/zig /usr/local/bin/zig
RUN curl -fsSL -o /tmp/node.tar.xz https://nodejs.org/dist/v${NODE_VERSION}/node-v${NODE_VERSION}-linux-arm64.tar.xz \
 && echo "${NODE_SHA256}  /tmp/node.tar.xz" | sha256sum -c - \
 && tar -xJf /tmp/node.tar.xz -C /usr/local --strip-components=1 && rm /tmp/node.tar.xz

ENV PATH=/usr/lib/llvm-${LLVM_MAJOR}/bin:$PATH
WORKDIR /work
