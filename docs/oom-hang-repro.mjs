// Minimal reproducer for the unkernel OOM livelock (docs/upstream/oom-hang.md). Needs only `npm i unkernel@0.2.0-261119-040e142` (Node >= 24).
//   node oom-hang-repro.mjs [boots=3] [kills=5]       (kernel: the one bundled in the package; or KERNEL=/path/to/unkernel.wasm)
// Guest: 128 MiB RAM; each round makes the guest allocate ~200 MB in a shell variable (head | tr | $(...)), so the kernel must OOM-kill it.
// Expected: every round ends within ~6-15 s ("exit=null" is how exec reports the killed shell). Actual on the unpatched kernel: a round never ends,
// the Node process sits at ~100% CPU (one core), the guest console prints nothing more; more likely with the host busy (run 3 copies at once).
import { createKernel } from "unkernel";
import { readFileSync } from "node:fs";
const boots = +(process.argv[2] ?? 3), kills = +(process.argv[3] ?? 5);
const STALL_MS = 120_000;
const t0 = Date.now();
for (let b = 1; b <= boots; b++) {
  const vm = await createKernel({ memoryMiB: 128, worker: false, ...(process.env.KERNEL ? { kernel: readFileSync(process.env.KERNEL) } : {}) });
  for (let i = 1; i <= kills; i++) {
    const s = Date.now();
    // A blocked event loop cannot time itself out: the watchdog is a second thread (child process) in practice; here we just print progress and
    // let the caller (or `timeout`) kill the process when a round does not finish.
    process.stdout.write(`boot ${b} kill ${i} ... `);
    const r = await vm.exec("sh", ["-c", 'x=$(head -c 200000000 /dev/zero | tr "\\0" a); echo done=${#x}']);
    console.log(`ok exit=${r.exitCode} ${Date.now() - s} ms (t=${Math.round((Date.now() - t0) / 1000)} s)`);
  }
  await vm.exec("poweroff", []).catch(() => {});
}
console.log("ALL ROUNDS FINISHED");
process.exit(0);
