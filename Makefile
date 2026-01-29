# nanUX Makefile (musl-based, i686)

SHELL := /bin/sh

# -------------------------------------------------------------------
# Global config
# -------------------------------------------------------------------

TARGET   := i686-linux-musl
TRIPLET  := $(TARGET)
PREFIX   := $(CURDIR)/cross
PATH     := $(PREFIX)/bin:$(PATH)

OUT      := $(CURDIR)/out
BUILD    := $(CURDIR)/build
SRC      := $(CURDIR)/src
ROOTFS   := $(CURDIR)/rootfs
ISO      := $(OUT)/nanux.iso
IMG      := $(OUT)/nanux.img

JOBS ?= $(shell \
  sysctl -n hw.logicalcpu 2>/dev/null || \
  getconf _NPROCESSORS_ONLN 2>/dev/null || \
  nproc 2>/dev/null || \
  echo 1)

# Host compiler

UNAME_S := $(shell uname -s)

ifeq ($(UNAME_S),Darwin)
	export CC := gcc-15
	export CXX := g++-15
else
	export CC := gcc
	export CXX := g++
endif

# -------------------------------------------------------------------
# Versions
# -------------------------------------------------------------------

BINUTILS_VERSION = 2.43.1
GCC_VERSION      = 14.3.0
MUSL_VERSION     = 1.2.5
LINUX_VERSION    = 6.1.159
BUSYBOX_VERSION  = 1.37.0
SYSLINUX_VERSION = 6.03
XORRISO_VERSION  = 1.5.6
DOSFSTOOLS_VERSION = 4.2

# -------------------------------------------------------------------
# URLs
# -------------------------------------------------------------------

GNU_MIRROR    = https://ftp.gnu.org/gnu
KERNEL_MIRROR = https://cdn.kernel.org/pub/linux/kernel/v6.x
BUSYBOX_URL   = https://busybox.net/downloads/busybox-$(BUSYBOX_VERSION).tar.bz2
MUSL_URL      = https://musl.libc.org/releases/musl-$(MUSL_VERSION).tar.gz
SYSLINUX_URL  = https://www.kernel.org/pub/linux/utils/boot/syslinux/syslinux-$(SYSLINUX_VERSION).tar.xz
XORRISO_URL   = https://www.gnu.org/software/xorriso/xorriso-$(XORRISO_VERSION).tar.gz
DOSFSTOOLS_URL = https://github.com/dosfstools/dosfstools/releases/download/v$(DOSFSTOOLS_VERSION)/dosfstools-$(DOSFSTOOLS_VERSION).tar.gz

# -------------------------------------------------------------------
# Output artifacts
# -------------------------------------------------------------------

INITRAMFS := $(OUT)/initramfs.cpio.gz
BZIMAGE   := $(OUT)/bzImage

# -------------------------------------------------------------------
# Stamp files
# -------------------------------------------------------------------

BINUTILS_STAMP   := $(PREFIX)/.binutils-built
GCC_INIT_STAMP   := $(PREFIX)/.gcc-initial-built
LINUX_HDR_STAMP  := $(PREFIX)/.linux-headers-built
MUSL_STAMP       := $(PREFIX)/.musl-built
GCC_FINAL_STAMP  := $(PREFIX)/.gcc-final-built
BUSYBOX_STAMP    := $(OUT)/.busybox-built
ROOTFS_STAMP     := $(OUT)/.rootfs-built
INITRAMFS_STAMP  := $(OUT)/.initramfs-built
KERNEL_STAMP     := $(OUT)/.kernel-built
SYSLINUX_STAMP   := $(OUT)/.syslinux-built
XORRISO_STAMP    := $(OUT)/.xorriso-built
DOSFSTOOLS_STAMP := $(OUT)/.dosfstools-built
ISO_STAMP        := $(OUT)/.iso-built
IMG_STAMP        := $(OUT)/.img-built

# -------------------------------------------------------------------
# Directories
# -------------------------------------------------------------------

$(OUT) $(BUILD) $(SRC) $(ROOTFS) $(PREFIX):
	@mkdir -p $@

# -------------------------------------------------------------------
# Top-level targets
# -------------------------------------------------------------------

.PHONY: all
all: toolchain kernel initramfs iso img

.PHONY: toolchain
toolchain: binutils gcc-initial musl gcc-final

# -------------------------------------------------------------------
# Binutils
# -------------------------------------------------------------------

BINUTILS_TAR := $(SRC)/binutils-$(BINUTILS_VERSION).tar.xz

$(BINUTILS_TAR): | $(SRC)
	curl -L $(GNU_MIRROR)/binutils/binutils-$(BINUTILS_VERSION).tar.xz -o $@

$(BINUTILS_STAMP): $(BINUTILS_TAR) | $(BUILD) $(PREFIX)
	@echo ">>> Building binutils"
	tar -C $(BUILD) -xf $(BINUTILS_TAR)
	mkdir -p $(BUILD)/build-binutils
	cd $(BUILD)/build-binutils && \
		../binutils-$(BINUTILS_VERSION)/configure \
			--target=$(TRIPLET) \
			--prefix=$(PREFIX) \
			--disable-nls \
			--disable-werror && \
		$(MAKE) MAKEINFO=true -j$(JOBS) && \
		$(MAKE) MAKEINFO=true install
	touch $@

binutils: $(BINUTILS_STAMP)

# -------------------------------------------------------------------
# GCC initial (C only)
# -------------------------------------------------------------------

GCC_TAR := $(SRC)/gcc-$(GCC_VERSION).tar.xz

$(GCC_TAR): | $(SRC)
	curl -L $(GNU_MIRROR)/gcc/gcc-$(GCC_VERSION)/gcc-$(GCC_VERSION).tar.xz -o $@

$(GCC_INIT_STAMP): $(BINUTILS_STAMP) $(GCC_TAR) | $(BUILD)
	@echo ">>> Building gcc initial"
	tar -C $(BUILD) -xf $(GCC_TAR)
	cd $(BUILD)/gcc-$(GCC_VERSION) && \
		./contrib/download_prerequisites
	mkdir -p $(BUILD)/build-gcc-initial
	cd $(BUILD)/build-gcc-initial && \
		../gcc-$(GCC_VERSION)/configure \
			--target=$(TRIPLET) \
			--prefix=$(PREFIX) \
			--disable-nls \
			--enable-languages=c \
			--without-headers \
			--disable-shared \
			--disable-threads \
			--disable-libssp \
			--disable-libgomp \
			--disable-libatomic \
			--disable-libquadmath && \
		$(MAKE) -j$(JOBS) all-gcc all-target-libgcc && \
		$(MAKE) install-gcc install-target-libgcc
	touch $@

.PHONY: gcc-initial
gcc-initial: $(GCC_INIT_STAMP)

# -------------------------------------------------------------------
# Linux headers
# -------------------------------------------------------------------

LINUX_TAR := $(SRC)/linux-$(LINUX_VERSION).tar.xz

$(LINUX_TAR): | $(SRC)
	curl -L $(KERNEL_MIRROR)/linux-$(LINUX_VERSION).tar.xz -o $@

$(LINUX_HDR_STAMP): $(GCC_INIT_STAMP) $(LINUX_TAR) | $(BUILD) $(PREFIX)
	@echo ">>> Installing linux headers"
	tar -C $(BUILD) -xf $(LINUX_TAR)
	cd $(BUILD)/linux-$(LINUX_VERSION) && \
		$(MAKE) INSTALL_HDR_PATH=$(PREFIX)/$(TRIPLET) headers_install
	touch $@

.PHONY: linux-headers
linux-headers: $(LINUX_HDR_STAMP)

# -------------------------------------------------------------------
# musl libc
# -------------------------------------------------------------------

MUSL_TAR := $(SRC)/musl-$(MUSL_VERSION).tar.gz

$(MUSL_TAR): | $(SRC)
	curl -L $(MUSL_URL) -o $@

$(MUSL_STAMP): $(LINUX_HDR_STAMP) $(MUSL_TAR) | $(BUILD)
	@echo ">>> Building musl"
	tar -C $(BUILD) -xf $(MUSL_TAR)
	cd $(BUILD)/musl-$(MUSL_VERSION) && \
		CC=$(TRIPLET)-gcc \
		./configure \
		  --target=$(TRIPLET) \
			--prefix=$(PREFIX)/$(TRIPLET) && \
		$(MAKE) -j$(JOBS) && \
		$(MAKE) install
	touch $@

.PHONY: musl
musl: $(MUSL_STAMP)

# -------------------------------------------------------------------
# GCC final (C + C++)
# -------------------------------------------------------------------

$(GCC_FINAL_STAMP): $(MUSL_STAMP) | $(BUILD)
	@echo ">>> Building gcc final"
	mkdir -p $(BUILD)/build-gcc-final
	cd $(BUILD)/build-gcc-final && \
		../gcc-$(GCC_VERSION)/configure \
			--target=$(TRIPLET) \
			--prefix=$(PREFIX) \
			--enable-languages=c,c++ \
			--disable-multilib \
			--disable-libitm \
			--disable-libsanitizer \
			--disable-libquadmath \
			--disable-libgomp && \
		$(MAKE) -j$(JOBS) && \
		$(MAKE) install
	touch $@

.PHONY: gcc-final
gcc-final: $(GCC_FINAL_STAMP)

# -------------------------------------------------------------------
# BusyBox (static)
# -------------------------------------------------------------------

BUSYBOX_TAR := $(SRC)/busybox-$(BUSYBOX_VERSION).tar.bz2

$(BUSYBOX_TAR): | $(SRC)
	curl -L $(BUSYBOX_URL) -o $@

$(BUSYBOX_STAMP): $(GCC_FINAL_STAMP) $(LINUX_HDR_STAMP) $(BUSYBOX_TAR) | $(ROOTFS) $(OUT)
	@echo ">>> Building BusyBox (static)"
	tar -C $(BUILD) -xf $(BUSYBOX_TAR)
	cd $(BUILD)/busybox-$(BUSYBOX_VERSION) && \
		make CROSS_COMPILE=$(TRIPLET)- defconfig && \
		sed -i 's/^# CONFIG_STATIC is not set/CONFIG_STATIC=y/' .config && \
		sed -i 's/^CONFIG_STATIC=.*/CONFIG_STATIC=y/' .config || echo "CONFIG_STATIC=y" >> .config && \
		make CROSS_COMPILE=$(TRIPLET)- LDFLAGS="-static" -j$(JOBS) && \
		make CROSS_COMPILE=$(TRIPLET)- CONFIG_PREFIX=$(ROOTFS) install
	touch $@

.PHONY: busybox
busybox: $(BUSYBOX_STAMP)

# -------------------------------------------------------------------
# Rootfs + improved initramfs
# -------------------------------------------------------------------

$(ROOTFS_STAMP): $(BUSYBOX_STAMP) | $(OUT)
	@echo ">>> Preparing rootfs"
	install -d -m 0755 $(ROOTFS)/etc $(ROOTFS)/proc $(ROOTFS)/sys \
		$(ROOTFS)/dev $(ROOTFS)/run $(ROOTFS)/root $(ROOTFS)/mnt
	install -d -m 1777 $(ROOTFS)/tmp
	@echo ">>> Creating /etc/passwd and /etc/group"
	@echo "root::0:0:root:/root:/bin/sh" > $(ROOTFS)/etc/passwd
	@echo "root:x:0:" > $(ROOTFS)/etc/group
	@echo ">>> Creating /etc/rc startup script"
	@echo "#!/bin/sh" > $(ROOTFS)/etc/rc
	@echo "mount -t proc proc /proc" >> $(ROOTFS)/etc/rc
	@echo "mount -t sysfs sys /sys" >> $(ROOTFS)/etc/rc
	@echo "mount -t devtmpfs dev /dev" >> $(ROOTFS)/etc/rc
	@echo "echo \"nanux (i686-linux-musl)\"" >> $(ROOTFS)/etc/rc
	@echo "cat /etc/motd" >> $(ROOTFS)/etc/rc
	chmod +x $(ROOTFS)/etc/rc
	@echo ">>> Creating /etc/inittab for BusyBox init"
	@echo "::sysinit:/etc/rc" > $(ROOTFS)/etc/inittab
	@echo "tty1::respawn:/bin/sh" >> $(ROOTFS)/etc/inittab
	@echo "tty2::respawn:/bin/sh" >> $(ROOTFS)/etc/inittab
	@echo "tty3::respawn:/bin/sh" >> $(ROOTFS)/etc/inittab
	@echo "tty4::respawn:/bin/sh" >> $(ROOTFS)/etc/inittab
	@echo "ttyS0::respawn:/bin/sh" >> $(ROOTFS)/etc/inittab
	@echo "::ctrlaltdel:/sbin/reboot" >> $(ROOTFS)/etc/inittab
	@echo "::shutdown:/sbin/swapoff -a" >> $(ROOTFS)/etc/inittab
	@echo "::shutdown:/bin/umount -a -r" >> $(ROOTFS)/etc/inittab
	@echo ">>> Creating /etc/motd"
	@printf ":::.    :::.  :::.   :::.    :::. ...    :::  .,::      .:\n" > $(ROOTFS)/etc/motd
	@printf "\`;;;;,  \`;;;  ;;\`;;  \`;;;;,  \`;;; ;;     ;;;  \`;;;,  .,;; \n" >> $(ROOTFS)/etc/motd
	@printf "  [[[[[. '[[ ,[[ '[[,  [[[[[. '[[[['     [[[    '[[,,[['  \n" >> $(ROOTFS)/etc/motd
	@printf "  $$$ \"Y$$c$$$$cc$$$$c $$$ \"Y$$c$$$$      $$$     Y$$$$P    \n" >> $(ROOTFS)/etc/motd
	@printf "  888    Y88 888   888,888    Y8888    .d888   oP\"\`\`\"Yo,  \n" >> $(ROOTFS)/etc/motd
	@printf "  MMM     YM YMM   \"\"\` MMM     YM \"YmmMMMM\"\",m\"       \"Mm, \n" >> $(ROOTFS)/etc/motd
	touch $@

.PHONY: rootfs
rootfs: $(ROOTFS_STAMP)

$(INITRAMFS_STAMP): $(ROOTFS_STAMP) | $(OUT)
	@echo ">>> Creating initramfs"
	@if [ ! -f $(ROOTFS)/sbin/init ]; then \
		echo "Error: $(ROOTFS)/sbin/init not found! BusyBox must be installed first."; \
		exit 1; \
	fi
	@if [ ! -f $(ROOTFS)/etc/rc ]; then \
		echo "Error: $(ROOTFS)/etc/rc not found!"; \
		exit 1; \
	fi
	@if [ ! -x $(ROOTFS)/etc/rc ]; then \
		echo "Warning: $(ROOTFS)/etc/rc is not executable, fixing..."; \
		chmod +x $(ROOTFS)/etc/rc; \
	fi
	cd $(ROOTFS) && find . -print0 | cpio --null -ov --format=newc | gzip -9 > $(INITRAMFS)
	touch $@

.PHONY: initramfs
initramfs: $(INITRAMFS_STAMP)

# -------------------------------------------------------------------
# Kernel
# -------------------------------------------------------------------

$(KERNEL_STAMP): $(GCC_FINAL_STAMP) $(LINUX_HDR_STAMP) $(LINUX_TAR) | $(OUT) $(BUILD)
	@echo ">>> Building kernel (cross-compiling for i686)"
	tar -C $(BUILD) -xf $(LINUX_TAR)
	cd $(BUILD)/linux-$(LINUX_VERSION) && \
		$(MAKE) ARCH=x86 CROSS_COMPILE=$(TRIPLET)- HOSTCC=$(CC) HOSTCXX=$(CXX) i386_defconfig && \
		scripts/config --enable CONFIG_DEVTMPFS 2>/dev/null || true && \
		scripts/config --enable CONFIG_DEVTMPFS_MOUNT 2>/dev/null || true && \
		$(MAKE) ARCH=x86 CROSS_COMPILE=$(TRIPLET)- HOSTCC=$(CC) HOSTCXX=$(CXX) -j$(JOBS) bzImage && \
		cp $(BUILD)/linux-$(LINUX_VERSION)/arch/x86/boot/bzImage $(BZIMAGE)
	touch $@

.PHONY: kernel
kernel: $(KERNEL_STAMP)

# -------------------------------------------------------------------
# Syslinux (ISOLINUX)
# -------------------------------------------------------------------

SYSLINUX_TAR := $(SRC)/syslinux-$(SYSLINUX_VERSION).tar.xz

$(SYSLINUX_TAR): | $(SRC)
	curl -L $(SYSLINUX_URL) -o $@

$(SYSLINUX_STAMP): $(SYSLINUX_TAR) $(GCC_FINAL_STAMP) $(MUSL_STAMP) | $(OUT) $(BUILD)
	@echo ">>> Building syslinux"
	tar -C $(BUILD) -xf $(SYSLINUX_TAR)
	@if [ -f $(BUILD)/syslinux-$(SYSLINUX_VERSION)/com32/lib/syslinux/debug.c ] && ! grep -q "#include <stdio.h>" $(BUILD)/syslinux-$(SYSLINUX_VERSION)/com32/lib/syslinux/debug.c; then \
		echo "Patching syslinux to include stdio.h"; \
		sed -i '1a#include <stdio.h>' $(BUILD)/syslinux-$(SYSLINUX_VERSION)/com32/lib/syslinux/debug.c; \
	fi
	@if [ -f $(BUILD)/syslinux-$(SYSLINUX_VERSION)/com32/gplinclude/memory.h ]; then \
		echo "Patching syslinux to fix e820_types multiple definition"; \
		sed -i 's/^\([^/]*e820_types[^;]*\);$$/extern \1;/' $(BUILD)/syslinux-$(SYSLINUX_VERSION)/com32/gplinclude/memory.h || true; \
	fi
	cd $(BUILD)/syslinux-$(SYSLINUX_VERSION) && \
		$(MAKE) CC=$(TRIPLET)-gcc \
			LD=$(TRIPLET)-ld \
			AR=$(TRIPLET)-ar \
			OBJCOPY=$(TRIPLET)-objcopy \
			STRIP=$(TRIPLET)-strip \
			CFLAGS="$${CFLAGS} -I$(PREFIX)/$(TRIPLET)/include -fcommon" \
			-j$(JOBS) bios/core/isolinux.bin bios/com32/elflink/ldlinux/ldlinux.c32 bios/linux/syslinux || \
		($(MAKE) CC=$(TRIPLET)-gcc \
			LD=$(TRIPLET)-ld \
			AR=$(TRIPLET)-ar \
			OBJCOPY=$(TRIPLET)-objcopy \
			STRIP=$(TRIPLET)-strip \
			CFLAGS="$${CFLAGS} -I$(PREFIX)/$(TRIPLET)/include -fcommon" \
			-j$(JOBS) bios/core bios/com32/elflink/ldlinux bios/linux 2>/dev/null || true)
	mkdir -p $(OUT)/syslinux
	cp $(BUILD)/syslinux-$(SYSLINUX_VERSION)/bios/core/isolinux.bin $(OUT)/syslinux/
	cp $(BUILD)/syslinux-$(SYSLINUX_VERSION)/bios/com32/elflink/ldlinux/ldlinux.c32 $(OUT)/syslinux/ 2>/dev/null || \
	cp $(BUILD)/syslinux-$(SYSLINUX_VERSION)/bios/com32/elflink/ldlinux/ldlinux.c32 $(OUT)/syslinux/ 2>/dev/null || true
	if [ -f $(BUILD)/syslinux-$(SYSLINUX_VERSION)/bios/linux/syslinux ]; then \
		cp $(BUILD)/syslinux-$(SYSLINUX_VERSION)/bios/linux/syslinux $(OUT)/syslinux/; \
	fi
	touch $@

.PHONY: syslinux
syslinux: $(SYSLINUX_STAMP)

# -------------------------------------------------------------------
# Xorriso
# -------------------------------------------------------------------

XORRISO_TAR := $(SRC)/xorriso-$(XORRISO_VERSION).tar.gz

$(XORRISO_TAR): | $(SRC)
	curl -L $(XORRISO_URL) -o $@

$(XORRISO_STAMP): $(XORRISO_TAR) | $(OUT) $(BUILD)
	@echo ">>> Building xorriso"
	tar -C $(BUILD) -xf $(XORRISO_TAR)
	cd $(BUILD)/xorriso-$(XORRISO_VERSION) && \
		./configure --prefix=$(OUT)/xorriso-install && \
		$(MAKE) -j$(JOBS) && \
		$(MAKE) install
	touch $@

.PHONY: xorriso
xorriso: $(XORRISO_STAMP)

# -------------------------------------------------------------------
# dosfstools (mkfs.vfat)
# -------------------------------------------------------------------

DOSFSTOOLS_TAR := $(SRC)/dosfstools-$(DOSFSTOOLS_VERSION).tar.gz

$(DOSFSTOOLS_TAR): | $(SRC)
	curl -L $(DOSFSTOOLS_URL) -o $@

$(DOSFSTOOLS_STAMP): $(DOSFSTOOLS_TAR) | $(OUT) $(BUILD)
	@echo ">>> Building dosfstools"
	tar -C $(BUILD) -xf $(DOSFSTOOLS_TAR)
	cd $(BUILD)/dosfstools-$(DOSFSTOOLS_VERSION) && \
		./configure --prefix=$(OUT)/dosfstools-install && \
		$(MAKE) -j$(JOBS) && \
		$(MAKE) install
	touch $@

.PHONY: dosfstools
dosfstools: $(DOSFSTOOLS_STAMP)

# -------------------------------------------------------------------
# ISO (BIOS, ISOLINUX)
# -------------------------------------------------------------------

$(ISO_STAMP): $(KERNEL_STAMP) $(INITRAMFS_STAMP) $(SYSLINUX_STAMP) $(XORRISO_STAMP) | $(OUT)
	@echo ">>> Building ISO"
	mkdir -p $(OUT)/iso/boot/isolinux
	cp $(BZIMAGE) $(OUT)/iso/boot/vmlinuz
	cp $(INITRAMFS) $(OUT)/iso/boot/initramfs.gz
	@echo ">>> Creating isolinux.cfg"
	@echo "DEFAULT nanux" > $(OUT)/iso/boot/isolinux/isolinux.cfg
	@echo "PROMPT 0" >> $(OUT)/iso/boot/isolinux/isolinux.cfg
	@echo "TIMEOUT 30" >> $(OUT)/iso/boot/isolinux/isolinux.cfg
	@echo "LABEL nanux" >> $(OUT)/iso/boot/isolinux/isolinux.cfg
	@echo "    KERNEL /boot/vmlinuz" >> $(OUT)/iso/boot/isolinux/isolinux.cfg
	@echo "    INITRD /boot/initramfs.gz" >> $(OUT)/iso/boot/isolinux/isolinux.cfg
	@echo "    APPEND console=tty0 console=ttyS0,115200 rdinit=/sbin/init rw" >> $(OUT)/iso/boot/isolinux/isolinux.cfg
	@echo ">>> Copying isolinux.bin"
	cp $(OUT)/syslinux/isolinux.bin $(OUT)/iso/boot/isolinux/
	@echo ">>> Copying ldlinux.c32"
	@if [ -f $(OUT)/syslinux/ldlinux.c32 ]; then \
		cp $(OUT)/syslinux/ldlinux.c32 $(OUT)/iso/boot/isolinux/; \
	fi
	@echo ">>> Creating ISO"
	$(OUT)/xorriso-install/bin/xorriso -as mkisofs -o $(ISO) \
		-b boot/isolinux/isolinux.bin \
		-c boot/isolinux/boot.cat \
		-no-emul-boot -boot-load-size 4 -boot-info-table \
		$(OUT)/iso
	touch $@

.PHONY: iso
iso: $(ISO_STAMP)

# -------------------------------------------------------------------
# IMG (raw USB image)
# -------------------------------------------------------------------

$(IMG_STAMP): $(ISO_STAMP) $(DOSFSTOOLS_STAMP) $(SYSLINUX_STAMP) | $(OUT)
	@echo ">>> Creating raw IMG"
	dd if=/dev/zero of=$(IMG) bs=1M count=64
	$(OUT)/dosfstools-install/sbin/mkfs.vfat -F 32 $(IMG)
	@echo ">>> Copying kernel and initramfs"
	@MTOOLS_SKIP_CHECK=1 mcopy -i $(IMG) $(BZIMAGE) ::/vmlinuz 2>/dev/null || \
		(echo "Warning: mcopy not found, trying alternative method"; \
		 mkdir -p $(OUT)/img-mount && \
		 sudo mount -o loop $(IMG) $(OUT)/img-mount 2>/dev/null && \
		 sudo cp $(BZIMAGE) $(OUT)/img-mount/vmlinuz && \
		 sudo umount $(OUT)/img-mount || true)
	@MTOOLS_SKIP_CHECK=1 mcopy -i $(IMG) $(INITRAMFS) ::/initramfs.gz 2>/dev/null || true
	@echo ">>> Copying ldlinux.c32"
	@MTOOLS_SKIP_CHECK=1 mcopy -i $(IMG) $(OUT)/syslinux/ldlinux.c32 ::/ldlinux.c32 2>/dev/null || true
	@if [ -f $(OUT)/syslinux/isolinux.bin ]; then \
		MTOOLS_SKIP_CHECK=1 mcopy -i $(IMG) $(OUT)/syslinux/isolinux.bin ::/isolinux.bin 2>/dev/null || true; \
	fi
	@echo ">>> Creating syslinux.cfg"
	@echo "DEFAULT nanux" > $(OUT)/syslinux.cfg
	@echo "PROMPT 0" >> $(OUT)/syslinux.cfg
	@echo "TIMEOUT 30" >> $(OUT)/syslinux.cfg
	@echo "LABEL nanux" >> $(OUT)/syslinux.cfg
	@echo "  KERNEL vmlinuz" >> $(OUT)/syslinux.cfg
	@echo "  INITRD initramfs.gz" >> $(OUT)/syslinux.cfg
	@echo "  APPEND console=tty0 console=ttyS0,115200 rdinit=/sbin/init rw" >> $(OUT)/syslinux.cfg
	@MTOOLS_SKIP_CHECK=1 mcopy -i $(IMG) $(OUT)/syslinux.cfg ::/syslinux.cfg 2>/dev/null || true
	@if [ -f $(OUT)/syslinux/syslinux ]; then \
		echo "Installing syslinux bootloader"; \
		$(OUT)/syslinux/syslinux $(IMG) 2>/dev/null || true; \
	elif [ -f $(BUILD)/syslinux-$(SYSLINUX_VERSION)/bios/linux/syslinux ]; then \
		echo "Installing syslinux bootloader from build"; \
		$(BUILD)/syslinux-$(SYSLINUX_VERSION)/bios/linux/syslinux $(IMG) 2>/dev/null || true; \
	elif command -v syslinux >/dev/null 2>&1; then \
		echo "Installing syslinux bootloader from system"; \
		syslinux $(IMG) 2>/dev/null || true; \
	else \
		echo "Warning: syslinux not found, image may not be bootable"; \
	fi
	touch $@

.PHONY: img
img: $(IMG_STAMP)

# -------------------------------------------------------------------
# QEMU
# -------------------------------------------------------------------

.PHONY: qemu-run
qemu-run: $(KERNEL_STAMP) $(INITRAMFS_STAMP)
	qemu-system-i386 -kernel $(BZIMAGE) -initrd $(INITRAMFS) -nographic

# -------------------------------------------------------------------
# Cleanup
# -------------------------------------------------------------------

.PHONY: clean
clean:
	rm -rf $(BUILD) $(ROOTFS)

.PHONY: distclean
distclean: clean
	rm -rf $(SRC) $(OUT) $(PREFIX)

