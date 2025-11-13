Kernel: [https://git.kernel.org/pub/scm/linux/kernel/git/riscv/linux.git/snapshot/linux-riscv-for-linus-6.18-rc6.tar.gz](https://git.kernel.org/pub/scm/linux/kernel/git/riscv/linux.git/snapshot/linux-riscv-for-linus-6.18-rc6.tar.gz)

Configuration: [here](config.log)

LLVM: [https://github.com/llvm/llvm-project/releases/download/llvmorg-21.1.5/LLVM-21.1.5-Linux-X64.tar.xz](https://github.com/llvm/llvm-project/releases/download/llvmorg-21.1.5/LLVM-21.1.5-Linux-X64.tar.xz)

When booting the kernel in QEMU, the error was traced to: `arch/riscv/kernel/tests/kprobes`. Log is [here](report0.log).

Specifically, in the file `arch/riscv/kernel/tests/kprobes/test-kprobes.c`, the following line fails:

```c
kp = kcalloc(num_kprobe, sizeof(*kp), GFP_KERNEL);
```

I added debugging output:

```c
while (test_kprobes_addresses[num_kprobe]) {
    pr_info("addr[%d] = %px\n", num_kprobe, test_kprobes_addresses[num_kprobe]);
    num_kprobe++;
}
pr_info("num_kprobe=%u\n", num_kprobe);
```

This revealed that the length of the `test_kprobes_addresses` array is abnormally large. See [here](vm.log).

According to the `arch/riscv/kernel/tests/kprobes/test-kprobes-asm.S` file, only 25 entries should be inserted into `test_kprobes_addresses`. Therefore, the array should not be this long.

When compiling the kernel with GCC, the kernel boots correctly. This indicates that the issue is specific to Clang: Clang misaligns the arrays or generates symbols incorrectly, causing `test_kprobes_addresses` to appear much larger than it actually is, even containing invalid addresses. Consequently, the `while(test_kprobes_addresses[num_kprobe])` loop overestimates `num_kprobe`, and `kcalloc` tries to allocate an excessively large memory block.

The solution is to explicitly apply `.align 3` (8-byte alignment) to both `test_kprobes_addresses` and `test_kprobes_functions`, place them in `.rodata`, and declare the symbols as global using `.global` to ensure consistent behavior between Clang and GCC.
