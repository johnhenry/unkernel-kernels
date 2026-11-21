# unkernel-kernels

Rebuilt kernels for [unkernel](https://github.com/pithings/unkernel) (Linux compiled to WebAssembly),
with the features containers need that the stock kernel leaves out, and the recipe that builds them.

| Kernel | What it is | Size |
|---|---|---|
| `unkernel-stock-tickfix` | The stock kernel plus one patch that fixes a hang when the guest runs out of memory. Nothing else changed | 10.1 MB |
| `unkernel-net-tickfix` | That fix, plus bridge devices; the `bpf` system call and cgroup BPF; keyrings; cgroup v2 `cpu`, `cpuset` and `memory` controllers. No netfilter, no seccomp | 11.6 MB |
| `unkernel-netfilter-tickfix` | Everything in `unkernel-net-tickfix`, plus netfilter: connection tracking, NAT, iptables (legacy) and nftables, bridge netfilter. No seccomp | 12.1 MB |
| `unkernel-net`, `unkernel-netfilter` (release `v040e142`) | The earlier builds, **without the fix. Superseded: do not use them where memory can run out** | 11.6 / 12.1 MB |

Download them from the [releases](../../releases) (the `-tickfix` files are in `v040e142-tickfix`), or as OCI artifacts from
`ghcr.io/johnhenry/unkernel-kernels` (tags `stock-tickfix-040e142`, `net-tickfix-040e142`, `netfilter-tickfix-040e142`; one
`application/wasm` layer whose digest is the file's sha256). Checksums are in [`SHA256SUMS`](SHA256SUMS).

## The out-of-memory hang, and the fix

**What happened.** When the guest ran out of memory, the kernel could spin at 100 % of one core forever instead of killing
the process that used too much. The earlier `net` and `netfilter` builds here did it often, and this README used to say the
stock kernel did not. That was wrong: **the unmodified kernel shipped in the `unkernel` npm package does it too.** On an idle
machine, three boots of the stock kernel and three of the old `net` kernel, five out-of-memory rounds each: none of the six
finished (they hung after 0 to 4 rounds). It was first blamed on the memory controller; a build without it still hung.

**Why.** This port of Linux has no asynchronous interrupt delivery: the timer tick is polled only when a program traps
from user mode back into the kernel, and in the idle loop. A loop that stays inside the kernel never sees the tick, so the
scheduler is never asked to switch tasks. Direct reclaim, retrying an allocation that can only succeed once *another* task
runs (for example the reader of a full pipe), is such a loop. A profile of a hung kernel shows all of its time in
`do_shrink_slab < shrink_slab < shrink_node < do_try_to_free_pages < __alloc_pages_direct_reclaim < __alloc_pages_slowpath`,
and the console never prints `invoked oom-killer`: the kernel does not get as far as the out-of-memory killer.

**The fix.** One patch ([`build/patches/linux-tickfix/`](build/patches/linux-tickfix), also in [`docs/`](docs)): the kernel
polls its pending timer and host interrupts from `cond_resched()`, where it already offers to yield, one call in 32.

| Kernel | Boots that finished the test | Out-of-memory kills |
|---|---|---|
| stock, unmodified (npm package) | 0 of 3 on an idle machine; 1 of 9 under load | — |
| `unkernel-net` (old) | 0 of 3 on an idle machine; 1 of 14 under load | — |
| built without the memory controller, no fix | 2 of 5 | — |
| `unkernel-stock-tickfix` | 4 of 4, and 4 of 4 again in an independent run | 40 |
| `unkernel-net-tickfix` | 12 of 12 global, 4 of 4 memory-cgroup, 3 of 3 with two CPUs; 4 of 4 again in an independent run | 135 |
| `unkernel-netfilter-tickfix` | 12 of 12 global, 4 of 4 memory-cgroup, 3 of 3 with two CPUs; 4 of 4 again in an independent run | 135 |

No measurable cost: boot time and a find / pipe / shell-loop workload are within noise of the unpatched kernels. With the fix,
`memory.max` is enforced and a process that exceeds it is killed while the kernel carries on.

**Reproduce it** with only the npm package: [`docs/oom-hang-repro.mjs`](docs/oom-hang-repro.mjs)
(`npm i unkernel@0.2.0-261119-040e142; node oom-hang-repro.mjs 3 5`; add `KERNEL=/path/to/a-tickfix.wasm` to see it pass).

**What is not established.** Why reclaim keeps retrying instead of giving up was not traced inside the kernel: the explanation
rests on the profile, the missing out-of-memory message, and the patch curing every variant tried. Other kernel-only loops
(writeback throttling, compaction) may need the same treatment. Whether the poll belongs in `cond_resched()` or in the
idle / relax / interrupt-enable primitives is a question for the upstream maintainers.

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

const bytes = new Uint8Array(await (await fetch("unkernel-net-tickfix-040e142.wasm")).arrayBuffer());
const vm = await createKernel({ kernel: bytes, memoryMiB: 512 });
const r = await vm.exec("sh", ["-c", "uname -r; ip link add br0 type bridge && ip link show br0"]);
console.log(r.stdout); // 7.3.4-dib-net-tickfix+ …
```

Each file is a complete bundle like the stock `unkernel.wasm`: kernel, initramfs, command line, data-disk
template and the multi-CPU patch.

## What was tested

The feature checks below were made on 2026-11-20 on the earlier builds; the `-tickfix` builds have the same configuration plus the patch, and were re-run on 2026-11-21 against the project's kernel tests (bridge, veth, NAT, containers through an OCI runtime), which pass.

| Check | `net` | `netfilter` |
|---|---|---|
| Boots (about 35 ms); `uname -r` reports `7.3.4-dib-net+` / `7.3.4-dib-netfilter+` | yes | yes |
| Boots with 2 CPUs | yes | yes |
| `ip link add br0 type bridge` | yes | yes |
| Two network namespaces joined by veth pairs on a bridge: ping and a TCP exchange between them | yes | — |
| `cgroup.controllers` lists `cpuset cpu memory pids` | yes | yes |
| `memory.max` and `cpu.max` are accepted; `cpu.max` throttles | yes | — |
| A process exceeding `memory.max` is killed and the kernel carries on | yes with `-tickfix`; unreliable on the old builds | yes with `-tickfix`; unreliable on the old builds |
| `crun run` with its default cgroup manager (the device-cgroup BPF program loads) | yes | yes |
| `/proc/net/netfilter` present; MASQUERADE and DNAT rules load; a DNAT from `127.0.0.1:8080` reaches a server in another namespace across the bridge | no netfilter, by design | yes |
| Repeated NAT + conntrack + bridge traffic (25 rounds on 1 CPU, 15 on 2 CPUs) without a kernel trap | — | yes |

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
build/build.sh stock               # reproduces upstream's kernel (a control)
build/build.sh stock-tickfix       # stock + the out-of-memory fix
build/build.sh net-tickfix
build/build.sh netfilter-tickfix
build/build.sh net                 # the earlier builds, without the fix
build/build.sh netfilter
```

Output goes to `out/`. Needs Docker on arm64 or x86-64, about 6 GB of disk, and 15 to 20 minutes for
the first build (most of it a patched `wasm-ld`). Nothing from the network is executed on the host:
the build runs in a container that mounts only `build/` (read-only), `out/` and a named volume.

Toolchain used for the published binaries: Debian trixie (arm64), clang and lld 22.1.8, Zig 0.16.0,
Node 24.22.3.

> The scripts were run as part of a larger project and copied here with their paths adjusted for this
> layout (`out/` instead of that project's directories). The adjusted copies have not been re-run.
> `build/fragments/*-nomemcg.config` are kept as a documented negative result: a kernel without the
> memory controller still hung.

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
