qemu-system-riscv64 \
  -cpu rv64,h=true,sscofpmf=true \
  -m 4096 \
  -smp 4 \
  -chardev socket,id=SOCKSYZ,server=on,wait=off,host=localhost,port=64250 \
  -mon chardev=SOCKSYZ,mode=control \
  -display none \
  -serial stdio \
  -no-reboot \
  -name VM-0 \
  -device virtio-rng-pci \
  -machine virt \
  -device virtio-net-pci,netdev=net0 \
  -netdev user,id=net0,restrict=on,hostfwd=tcp:127.0.0.1:18755-:22 \
  -device virtio-blk-device,drive=hd0 \
  -drive file=pathto/rootfs.ext2,if=none,format=raw,id=hd0 \
  -snapshot \
  -kernel pathto/arch/riscv/boot/Image \
  -append "root=/dev/vda console=ttyS0 ro earlycon nokaslr panic_on_warn=1" \
  2>&1 | tee vm.log 

    # -s -S \