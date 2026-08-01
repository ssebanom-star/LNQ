#### QEMU 11.0.3 version-specific options
#
# Everything here is expressed as flags for QEMU's ./configure, which since
# QEMU 5.2 is a thin wrapper that generates a meson cross file and runs
# "meson setup".  There is no Makefile.target to hook into any more.

######################################################################
# Limbo-specific meson options (see patches/qemu-11.0.3.patch)
######################################################################

# Build lib<name>.so instead of an executable so the app can dlopen() it.
QEMU_LIMBO_OPTS += -Dshared_emulator=true

# QEMU's project() sets b_staticpic=false, but every object that ends up in a
# shared library must be PIC. Without this meson refuses to link with
#   "Can't link non-PIC static library 'qemuutil' into shared library".
QEMU_LIMBO_OPTS += -Db_staticpic=true

# QEMU's project() also sets b_pie=true, which the linker rejects outright
# when building a shared object: "-shared and -pie may not be used together".
# A shared library is position independent by way of PIC; PIE is meaningless.
QEMU_LIMBO_OPTS += --disable-pie

# Do NOT add -Dprefer_static=true here. It is tempting, since glib/pixman/
# libslirp are installed as static archives, but meson applies it to *every*
# library including libc: the link then pulls in bionic's libc.a, which
# defines memfd_create() and collides with QEMU's own fallback definition in
# util/memfd.c (bionic only declares memfd_create from API 30, so QEMU's
# CONFIG_MEMFD probe fails and it supplies its own).
# Static linking of our dependencies happens anyway: $(LIMBO_PREFIX)/lib
# contains only .a files, so -lglib-2.0 has nothing else to resolve against.

######################################################################
# Features Limbo actually uses
######################################################################

ifeq ($(USE_SDL),true)
    QEMU_FEATURES += --enable-sdl
else
    QEMU_FEATURES += --disable-sdl
endif

ifeq ($(USE_SDL_AUDIO),true)
    QEMU_FEATURES += --audio-drv-list=sdl
else
    QEMU_FEATURES += --audio-drv-list=
endif

ifeq ($(USE_KVM),true)
    QEMU_FEATURES += --enable-kvm
else
    QEMU_FEATURES += --disable-kvm
endif

# User-mode networking. Since QEMU 8.0 slirp is no longer vendored; it must be
# supplied as an external libslirp via pkg-config.
QEMU_FEATURES += --enable-slirp

QEMU_FEATURES += --enable-vnc --disable-vnc-jpeg --disable-vnc-sasl

# ucontext is unreliable on bionic; sigaltstack is what Limbo has always used.
QEMU_FEATURES += --with-coroutine=sigaltstack

######################################################################
# Things that cannot or should not be built for Android
######################################################################

# No display backends other than SDL/VNC.
QEMU_DISABLE += --disable-gtk --disable-curses --disable-cocoa
QEMU_DISABLE += --disable-opengl --disable-virglrenderer --disable-vte

# vhost-user and VDUSE do not build against bionic: their bundled
# standard-headers/linux/virtio_ring.h collides with the NDK's UAPI headers,
# and libvhost-user calls memfd_create() without declaring it. None of it is
# reachable from Limbo anyway.
QEMU_DISABLE += --disable-vhost-user --disable-vhost-vdpa --disable-vhost-kernel
QEMU_DISABLE += --disable-vhost-net --disable-vhost-crypto
QEMU_DISABLE += --disable-vhost-user-blk-server
QEMU_DISABLE += --disable-libvduse --disable-vduse-blk-export
QEMU_DISABLE += --disable-multiprocess

# Host services with no Android equivalent.
QEMU_DISABLE += --disable-linux-aio --disable-linux-io-uring
QEMU_DISABLE += --disable-attr --disable-virtfs --disable-cap-ng
QEMU_DISABLE += --disable-seccomp --disable-libudev --disable-selinux
QEMU_DISABLE += --disable-xen --disable-rdma --disable-numa
QEMU_DISABLE += --disable-dbus-display --disable-tpm --disable-smartcard
QEMU_DISABLE += --disable-usb-redir --disable-libusb --disable-brlapi
QEMU_DISABLE += --disable-spice --disable-spice-protocol

# Crypto/compression backends we do not ship.
QEMU_DISABLE += --disable-gnutls --disable-nettle --disable-gcrypt
QEMU_DISABLE += --disable-bzip2 --disable-lzo --disable-snappy --disable-zstd
QEMU_DISABLE += --disable-curl --disable-libssh --disable-libnfs
QEMU_DISABLE += --disable-libiscsi --disable-rbd --disable-glusterfs

# Rust is optional in QEMU 11 and needs rustc >= 1.83 plus bindgen; skipping it
# keeps the toolchain requirement to "the NDK".
QEMU_DISABLE += --disable-rust

# Only the emulator itself is packaged into the APK.
QEMU_DISABLE += --disable-tools --disable-guest-agent --disable-docs
QEMU_DISABLE += --disable-user --disable-plugins --disable-fuse

# libfdt is only needed by targets with a device tree (arm, ppc, riscv...).
# For an x86-only build it can be skipped entirely; otherwise cross-build dtc
# into $(LIMBO_PREFIX) and drop this line.
ifeq ($(BUILD_GUEST),x86_64-softmmu)
    QEMU_DISABLE += --disable-fdt
else
    QEMU_FEATURES += --enable-fdt=system
endif

######################################################################
# Debug / optimisation
######################################################################

ifeq ($(NDK_DEBUG),1)
    QEMU_DEBUG = --enable-debug
else
    QEMU_DEBUG = --disable-debug-tcg --disable-debug-info
endif
