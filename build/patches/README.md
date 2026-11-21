# patches/

| file | applies to | origin | licence |
|---|---|---|---|
| `linux/0001-kconfig-allow-CPUSETS-on-uniprocessor-kernels.patch` | Linux tree (arch/wasm UP) | https://github.com/gregbell/linux-wasm-unk8s commit 44faf65f (fetched as `.../commit/44faf65f.patch`), unmodified | GPL-2.0 (Linux kernel) |
| `linux/0002-wasm-resolve-the-undefined-symbols-the-unk8s-config-exposes.patch` | Linux tree | the same fork, commit e0b28909, unmodified. Adds a UP no-op `dl_rebuild_rd_accounting()` (CPUSETS on UP) and a `get_vm_area()` stub returning NULL in `mm/vmalloc-flat.c` (BPF arena) | GPL-2.0 |
| `0001-build-extra-frags.patch` (generated at build time by `in-container.sh`, copy kept here) | `pithings/unkernel` `kernel/build.sh` | this repo: adds `KW_EXTRA_FRAGS` so extra fragments are merged into BOTH the UP and SMP kernels and checked by upstream's `check_config` | GPL-2.0-or-later (upstream's licence for the script) |

`guest-tools/iproute2-static-linkutil.pl` is a test-tool patch (static `ip` cannot `dlsym` its built-in link types); not part of any kernel.
| `linux-tickfix/0003-wasm-poll-the-timer-tick-from-cond_resched.patch` (only for the `*-tickfix` variants) | Linux tree (arch/wasm, kernel/sched/core.c) | written for this repository (2026-11-21), also drafted as an upstream report in docs/upstream/oom-hang.md | GPL-2.0 |
