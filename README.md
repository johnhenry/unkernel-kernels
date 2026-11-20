# unkernel-kernels

Rebuilt kernels for [unkernel](https://github.com/pithings/unkernel) (Linux compiled to WebAssembly),
with the features containers need that the stock kernel leaves out, and the recipe that builds them.

| Kernel | Adds to the stock kernel | Still lacks | Size |
|---|---|---|---|
| `unkernel-net` | Bridge devices; the `bpf` system call and cgroup BPF; keyrings; cgroup v2 `cpu`, `cpuset` and `memory` controllers | Netfilter, seccomp | 11.6 MB |
| `unkernel-netfilter` | Everything in `unkernel-net`, plus netfilter: connection tracking, NAT, iptables (legacy) and nftables, bridge netfilter | seccomp | 12.1 MB |

Download them from the [releases](../../releases). Checksums are in [`SHA256SUMS`](SHA256SUMS).

> **Known defect: an out-of-memory kill can hang these kernels.** When a process is killed for
> exceeding a memory limit (`memory.max`), or when the whole guest runs out of memory, the first kill
> usually works and a later one (typically the second to the sixth in one boot) hangs the kernel. The
> stock kernel does not do this. Do not rely on memory limits with these builds. Details below.

## Compatibility: one SDK version only

These kernels are built from upstream commit
[`040e142`](https://github.com/pithings/unkernel/commit/040e142cd016da066ac018de60fcdcec3201fd24)
(tag `v0.2.0-261119-040e142`) and work with the npm package **`unkernel@0.2.0-261119-040e142`**.

The interface between an unkernel kernel and its JavaScript SDK is private and changes often. A kernel
from one commit may not boot with the SDK from another. Use these with exactly that SDK version, and
rebuild for any other.

## Using one

```js
import { createKernel } from "unkernel"; // 0.2.0-261119-040e142

const bytes = new Uint8Array(await (await fetch("unkernel-net-040e142.wasm")).arrayBuffer());
const vm = await createKernel({ kernel: bytes, memoryMiB: 512 });
const r = await vm.exec("sh", ["-c", "uname -r; ip link add br0 type bridge && ip link show br0"]);
console.log(r.stdout); // 7.3.4-dib-net+ …
```

Each file is a complete bundle like the stock `unkernel.wasm`: kernel, initramfs, command line, data-disk
template and the multi-CPU patch.

## What was tested

Built and tested on 2026-11-20, under Node 26 with the SDK version above.

| Check | `net` | `netfilter` |
|---|---|---|
| Boots (about 35 ms); `uname -r` reports `7.3.4-dib-net+` / `7.3.4-dib-netfilter+` | yes | yes |
| Boots with 2 CPUs | yes | yes |
| `ip link add br0 type bridge` | yes | yes |
| Two network namespaces joined by veth pairs on a bridge: ping and a TCP exchange between them | yes | — |
| `cgroup.controllers` lists `cpuset cpu memory pids` | yes | yes |
| `memory.max` and `cpu.max` are accepted; `cpu.max` throttles | yes | — |
| A process exceeding `memory.max` is killed and the kernel carries on | **unreliable: see "Known defect"** | **unreliable** |
| `crun run` with its default cgroup manager (the device-cgroup BPF program loads) | yes | yes |
| `/proc/net/netfilter` present; MASQUERADE and DNAT rules load; a DNAT from `127.0.0.1:8080` reaches a server in another namespace across the bridge | no netfilter, by design | yes |
| Repeated NAT + conntrack + bridge traffic (25 rounds on 1 CPU, 15 on 2 CPUs) without a kernel trap | — | yes |

### Known defect: out-of-memory kills

Reproduced on both kernels, single-CPU, under Node:

- **Memory-cgroup limit.** The first kill of a process over `memory.max` works (exit 137, `oom_kill 1`,
  the kernel keeps serving). A later kill in the same boot hangs the kernel.
- **Whole-guest exhaustion.** A 128 MiB guest allocating 200 MB five times: the stock kernel completes
  five of five; these kernels hang on the first or second kill.
- **Not the cause:** `cpu.max`, `oom_dump_tasks=0`, console logging off, `oom_kill_allocating_task=1`,
  or the cpuset controller (a build without it also hangs). A plain `kill -9` inside a memory cgroup
  works every time, and allocation without reaching the limit works every time.
- **Suspect, not confirmed:** `CONFIG_MEMCG`. A build without it was not completed.

It is not root-caused. Until it is, treat `memory.max` on these kernels as unsafe: a container that
exceeds it may hang the machine instead of being killed.

What else this does **not** establish:

- Nothing here was run in a browser. The same kernel binary runs there, but it was not tested there.
- The netfilter load test is short. unkernel's kernel stacks are small (16 KiB shadow stacks with no
  overflow detection); the author of the configuration this is based on left netfilter out for that
  reason. Deep netfilter paths under sustained load may still trap, and a trap ends the session.
- No long-running or adversarial testing, and no security review. There is still no seccomp.

## How they are built

Everything is in [`build/`](build): a Dockerfile and scripts that, inside a Linux container, clone
upstream at the pinned commit, apply the patches, merge a configuration fragment, and run upstream's
own build.

```
build/build.sh stock        # reproduces upstream's kernel (a control)
build/build.sh net
build/build.sh netfilter
```

Output goes to `out/`. Needs Docker on arm64 or x86-64, about 6 GB of disk, and 15 to 20 minutes for
the first build (most of it a patched `wasm-ld`). Nothing from the network is executed on the host:
the build runs in a container that mounts only `build/` (read-only), `out/` and a named volume.

Toolchain used for the published binaries: Debian trixie (arm64), clang and lld 22.1.8, Zig 0.16.0,
Node 24.22.3.

> The scripts were run as part of a larger project and moved here with their paths adjusted for this
> layout (`out/` instead of that project's directories). The adjusted copies have not been re-run.

| Path | What |
|---|---|
| [`build/fragments/net.config`](build/fragments/net.config), [`netfilter.config`](build/fragments/netfilter.config) | The options requested |
| [`build/config-delta/`](build/config-delta) | What actually changed in the final configuration, against stock |
| [`configs/`](configs) | The complete final `.config` of each kernel (single-CPU and SMP), and of the stock rebuild |
| [`build/patches/`](build/patches) | Patches applied, with their origin |
| [`build/guest-tools/`](build/guest-tools) | How the static `ip`, `bridge`, `nft` and `iptables` used for testing were built |

The stock rebuild matched the published upstream kernel: same build banner and identical code
section, differing by 64 bytes overall.

## Credits

- [unkernel](https://github.com/pithings/unkernel) by Pooya Parsa and contributors: the kernel port,
  the emulator and the build system. These are builds of it, not a fork of its ideas.
- [gregbell/linux-wasm-unk8s](https://github.com/gregbell/linux-wasm-unk8s): the configuration this
  started from and two kernel patches, used unmodified (see [`build/patches/README.md`](build/patches/README.md)).
- The Linux kernel developers.

This repository is not affiliated with either project.

## Licence

The kernels are builds of the Linux kernel and of unkernel's kernel-side code, and are distributed
under the **GNU General Public License, version 2** ([`COPYING`](COPYING)). The corresponding source is
upstream unkernel at commit `040e142cd016da066ac018de60fcdcec3201fd24` (which pins its Linux source)
together with the patches, fragments and scripts in [`build/`](build). The scripts and fragments in
this repository are offered under the same licence.
