# KVM RISC-V AIA IMSIC Null Pointer Dereference Bug Report

This repository documents a null pointer dereference bug discovered in the Linux kernel's RISC-V KVM AIA IMSIC implementation through fuzzing.

## Background

I have been working on adapting syzkaller's KVM syscall templates for the RISC-V64 architecture. The goal was to enable syzkaller to effectively test RISC-V KVM code paths that were previously not covered by existing fuzzing efforts.

After completing the basic adaptation work, syzkaller was successfully able to reach and exercise RISC-V KVM code. I then started a fuzzing targeting RISC-V64 KVM, which uncovered this bug:

**"BUG: unable to handle kernel paging request in kvm_riscv_aia_imsic_has_attr"**

## Bug Discovery and Reproduction

When syzkaller detects a kernel crash, it saves the sequence of syscalls (test seeds) executed before the crash occurred. These syscalls are stored in the execution log.

For this specific bug:

- The execution log is saved in: [00-log.txt](00-log.txt)
- The kernel crash report is saved in: [01-report.txt](01-report.txt)

### Reproducing the Bug

Syzkaller provides a tool called `syz-repro` that attempts to reproduce crashes by repeatedly executing the syscall sequences from the execution log.

To reproduce this bug, I used the following command:

```bash
./syz-repro -config riscv-kvm.cfg 00-log.txt > 02-repro.txt 2>&1
```

This command:

1. Reads the syscall sequences from [00-log.txt](00-log.txt)
2. Repeatedly executes these sequences to trigger the crash
3. Logs the reproduction attempt to a file

**Before the fix:**

- The reproduction log is in: [02-repro.txt](02-repro.txt)
- The bug was successfully reproduced, confirming it's a real and reproducible issue

## Root Cause Analysis

### The Vulnerability

The bug is located in the `kvm_riscv_aia_imsic_has_attr()` function in `arch/riscv/kvm/aia_imsic.c`.

**Vulnerable code:**

```c
int kvm_riscv_aia_imsic_has_attr(struct kvm *kvm, unsigned long type)
{
    u32 isel, vcpu_id;
    struct imsic *imsic;
    struct kvm_vcpu *vcpu;

    if (!kvm_riscv_aia_initialized(kvm))
        return -ENODEV;

    vcpu_id = KVM_DEV_RISCV_AIA_IMSIC_GET_VCPU(type);
    vcpu = kvm_get_vcpu_by_id(kvm, vcpu_id);
    if (!vcpu)
        return -ENODEV;

    isel = KVM_DEV_RISCV_AIA_IMSIC_GET_ISEL(type);
    imsic = vcpu->arch.aia_context.imsic_state;  // ← imsic could be NULL
    return imsic_mrif_isel_check(imsic->nr_eix, isel);  // ← NULL dereference
}
```

### Why It Crashes

The function performs two checks:

1. ✅ Checks if AIA is initialized globally: `kvm_riscv_aia_initialized(kvm)`
2. ✅ Checks if the vcpu exists: `if (!vcpu)`
3. ❌ **Missing:** Does NOT check if `imsic_state` is initialized

When userspace calls the `KVM_HAS_DEVICE_ATTR` ioctl with the `KVM_DEV_RISCV_AIA_GRP_IMSIC` group before the vcpu's IMSIC state is fully initialized, `vcpu->arch.aia_context.imsic_state` will be `NULL`. Accessing `imsic->nr_eix` then causes a null pointer dereference.

### Crash Details

From [01-report.txt](01-report.txt):

```
Unable to handle kernel paging request at virtual address dfffffff00000001
CPU: 3 PID: 5733 Comm: syz.1.179 Not tainted 6.18.0-rc5
epc : kvm_riscv_aia_imsic_has_attr+0x464/0x50e arch/riscv/kvm/aia_imsic.c:998

Call Trace:
  kvm_riscv_aia_imsic_has_attr+0x464/0x50e
  aia_has_attr+0x128/0x2bc
  kvm_device_ioctl_attr+0x296/0x374
  kvm_device_ioctl+0x296/0x374
  ...
```

The address `dfffffff00000001` is a KASAN (Kernel Address Sanitizer) shadow memory address, indicating an attempt to access memory at a small offset from NULL.

## The Fix

The fix is straightforward: add a null pointer check for `imsic_state` before dereferencing it.

**Fixed code:**

```c
int kvm_riscv_aia_imsic_has_attr(struct kvm *kvm, unsigned long type)
{
    u32 isel, vcpu_id;
    struct imsic *imsic;
    struct kvm_vcpu *vcpu;

    if (!kvm_riscv_aia_initialized(kvm))
        return -ENODEV;

    vcpu_id = KVM_DEV_RISCV_AIA_IMSIC_GET_VCPU(type);
    vcpu = kvm_get_vcpu_by_id(kvm, vcpu_id);
    if (!vcpu)
        return -ENODEV;

    isel = KVM_DEV_RISCV_AIA_IMSIC_GET_ISEL(type);
    imsic = vcpu->arch.aia_context.imsic_state;
  
    // Add null pointer check
    if (!imsic)
        return -ENODEV;
  
    return imsic_mrif_isel_check(imsic->nr_eix, isel);
}
```

This fix:

- Follows the same error handling pattern as the existing checks in the function
- Returns `-ENODEV` (No such device) when the IMSIC state is not initialized
- Prevents the null pointer dereference

## Verification

After applying the fix, I ran the same reproduction command again:

```bash
./syz-repro -config riscv-kvm.cfg 00-log.txt > 03-fixed.log 2>&1
```

**After the fix:**

- The reproduction log is in: [03-fixed.txt](03-fixed.txt)
- The bug no longer reproduces - the kernel remains stable
- This confirms the fix is effective

## Directory Structure
```
.
├── 00-log.txt          # Original execution log from syzkaller
├── 01-report.txt       # Kernel crash report
├── 02-repro.txt        # Reproduction log (before fix)
├── 03-fixed.txt        # Reproduction log (after fix)
├── config              # Kernel build configuration
├── readme.md           # Documentation
├── riscv-kvm.cfg       # Syzkaller fuzzing configuration
└── syz-repro           # Reproducer tool
```