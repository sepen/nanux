# nanux

i686 nano-distro based on musl and busybox

## Building in your host

### Prepare your host environment

On Linux: make sure you have: `gcc`, `g++`, `make`, `curl`, `tar`, `xz-utils`.

On macOS: install via Homebrew:
```
brew install gnu-tar gnu-sed gcc make xz
export PATH="/usr/local/opt/gnu-tar/libexec/gnubin:$PATH"
```

### Run the build

This will create the cross toolchain in ./cross/ and a minimal i686 rootfs in `./out/rootfs`.
```
make all
make busybox
make rootfs
```

### Test the rootfs

With QEMU:
```
qemu-system-i386 -kernel /path/to/bzImage -initrd out/rootfs.cpio.gz -append "console=ttyS0" -nographic
```

It can be tested on chroot (i686 host os required, or x86_64 with command setarch i686):
```
sudo chroot out/rootfs /bin/sh
```

## Building inside Docker

### Builder container image

Run the following command in the same directory as your Dockerfile:
```
docker build -t builder-crux .
```

### Build all stages

Run container with source mounted
```
docker run --rm -it -v $(pwd):/src builder-crux bash
```

Inside container: run the build
```
cd /src
make stage1
make stage2
```


## Notes & Tips

- Dynamic BusyBox:
  BusyBox is dynamically linked against glibc, which means you must ship the runtime libraries (ld-linux.so.2, libc.so.6, etc.) inside /lib. The Makefile automatically copies the required libraries.

- No ld.so.cache needed:
  For such a minimal system, you don’t need to run ldconfig. Having /etc/ld.so.conf pointing to /lib is enough. The dynamic loader (ld-linux.so.2) will find libraries there.

- Cross vs Native:
  This setup builds a cross toolchain on your host (x86_64 → i686). You can then use it to compile additional packages for your mini distro.

- Extending the rootfs:
  Start by adding:
  - coreutils (GNU basic utilities)
  - dropbear or openssh (for SSH)
  - pkg-config and a package manager (optional)

- Static vs Dynamic:
  - Static BusyBox is simpler for bootstrapping (no runtime libs needed).
  - Dynamic BusyBox is closer to a “real” distro and reduces binary size duplication.

- Kernel choice:
  Any Linux 6.x kernel built with `CONFIG_IA32_EMULATION=y` and `CONFIG_DEVTMPFS=y` should boot this rootfs fine.

- Init script:
  The init file inside rootfs mounts /proc, /sys, /dev, then launches /bin/sh. You can expand it to include mounting disks, networking, etc.
