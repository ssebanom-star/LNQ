include android-limbo-build.mak
include android-config/android-qemu-config.mak

######################################################################
# Layout
######################################################################
#
# QEMU 11 builds out of tree with meson, so unlike the pre-5.2 pipeline
# nothing is generated inside ./qemu.
#
#   ./qemu                          patched QEMU source (see patches/)
#   ../obj/prefix/<ABI>             cross-built glib/pixman/libslirp + .pc files
#   ../obj/qemu-build/<ABI>         meson build directory
#   ../obj/local/<ABI>              ndk-build output (compat, SDL2, JNI)
#
QEMU_SRC_DIR   = $(LIMBO_JNI_ROOT)/qemu
QEMU_BUILD_DIR = $(abspath $(NDK_PROJECT_PATH)/obj/qemu-build/$(APP_ABI))
QEMU_LIB       = $(QEMU_BUILD_DIR)/lib$(QEMU_PROG_NAME).so

# BUILD_GUEST is "<arch>-softmmu"; the library is libqemu-system-<arch>.so
QEMU_PROG_NAME = qemu-system-$(subst -softmmu,,$(BUILD_GUEST))

NDK_BUILD = ndk-build
ndkbuild = cd $(NDK_PROJECT_PATH) && $(NDK_BUILD) -j $(BUILD_THREADS)
ndkclean = cd $(NDK_PROJECT_PATH) && $(NDK_BUILD) clean

LIMBO_PRJ_ROOT = ../../../..
LIMBO_APP_X86  = $(LIMBO_PRJ_ROOT)/limbo-android-x86/src/main
LIMBO_APP_ARM  = $(LIMBO_PRJ_ROOT)/limbo-android-arm/src/main
LIMBO_APP_PPC  = $(LIMBO_PRJ_ROOT)/limbo-android-ppc/src/main
LIMBO_APP_SPARC = $(LIMBO_PRJ_ROOT)/limbo-android-sparc/src/main

######################################################################
# pc-bios assets
#
# QEMU 11's pc-bios/ has a rather different shape from 5.1.0's: UEFI images
# ship bzip2-compressed (edk2-*.fd.bz2) and are decompressed at build time
# into the meson build directory, and there are new descriptors/ and dtb/
# subdirectories. Copy from the *installed* tree rather than the source tree
# so the decompressed firmware is picked up.
######################################################################
QEMU_DATADIR = $(QEMU_BUILD_DIR)/pc-bios

COPY_ROMS = mkdir -p ../assets/roms && \
	cp -rf $(QEMU_DATADIR)/*.bin $(QEMU_DATADIR)/*.rom $(QEMU_DATADIR)/*.img \
	       $(QEMU_DATADIR)/*.fd ../assets/roms/ 2>/dev/null; \
	cp -rf $(QEMU_DATADIR)/keymaps ../assets/roms/ 2>/dev/null; true

COPY_QEMU_VERSION = cp -f $(QEMU_SRC_DIR)/VERSION ../assets/QEMU_VERSION
COPY_RESOLV_CONF = mkdir -p ../assets/roms/etc/ && \
	printf "nameserver 8.8.8.8\n\n" > ../assets/roms/etc/resolv.conf

export

.PHONY: default limbo ndk clean-ndk deps config-qemu qemu install \
        install-common clean distclean check-tools help

default: limbo

######################################################################
# Host tool check
#
# QEMU 11 needs meson >= 1.5, ninja and python >= 3.9. Failing here with a
# clear message beats failing 20 minutes into a build.
######################################################################
check-tools:
	@command -v meson  >/dev/null || { echo "error: meson not found (>= 1.5 required)"; exit 1; }
	@command -v ninja  >/dev/null || { echo "error: ninja not found"; exit 1; }
	@command -v $(PKG_CONFIG) >/dev/null || { echo "error: $(PKG_CONFIG) not found"; exit 1; }
	@test -x $(CC) || { echo "error: $(CC) not found - check NDK_ROOT and NDK_PLATFORM_API"; exit 1; }
	@test -d $(QEMU_SRC_DIR) || { echo "error: $(QEMU_SRC_DIR) missing - see README.developers"; exit 1; }
	@echo "host tools OK: $$(meson --version) / ninja $$(ninja --version)"

######################################################################
# ndk-build parts: compat shims, SDL2, the JNI bridge
######################################################################
ndk:
	$(ndkbuild)

clean-ndk:
	-$(ndkclean)
	-rm -rf $(NDK_PROJECT_PATH)/obj/local

######################################################################
# Cross-built dependencies (glib, pixman, libslirp, zlib .pc)
######################################################################
deps:
	$(LIMBO_JNI_ROOT)/android-config/build-deps.sh \
		$(APP_ABI) $(NDK_ROOT) $(NDK_PLATFORM_API) $(LIMBO_PREFIX_ABS)

clean-deps:
	-rm -rf $(LIMBO_PREFIX_ABS)

######################################################################
# QEMU
######################################################################
config-qemu: check-tools
	mkdir -p $(QEMU_BUILD_DIR)
	cd $(QEMU_BUILD_DIR) && $(PKG_CONFIG_ENV) \
		$(QEMU_SRC_DIR)/configure $(QEMU_CONFIGURE_FLAGS)

qemu:
	$(PKG_CONFIG_ENV) ninja -C $(QEMU_BUILD_DIR) -j $(BUILD_THREADS) \
		lib$(QEMU_PROG_NAME).so
	$(COPY_ROMS)
	$(COPY_QEMU_VERSION)
	$(COPY_RESOLV_CONF)

clean-qemu:
	-rm -rf $(QEMU_BUILD_DIR)
	-rm -rf ../assets/roms/*

######################################################################
# Install into the app modules
######################################################################
install-common:
	mkdir -p ../jniLibs/$(APP_ABI_DIR)/
	cp -f $(NDK_PROJECT_PATH)/obj/local/$(APP_ABI)/*.so ../jniLibs/$(APP_ABI_DIR)/
ifneq ($(NDK_DEBUG),1)
	$(STRIP) ../jniLibs/$(APP_ABI_DIR)/*.so
endif

install: install-common
	mkdir -p $(LIMBO_APP_X86)/jniLibs/$(APP_ABI_DIR)/
	cp -f $(QEMU_LIB) $(LIMBO_APP_X86)/jniLibs/$(APP_ABI_DIR)/
ifneq ($(NDK_DEBUG),1)
	$(STRIP) $(LIMBO_APP_X86)/jniLibs/$(APP_ABI_DIR)/lib$(QEMU_PROG_NAME).so
endif
	mkdir -p $(LIMBO_APP_X86)/assets/
	cp -rf ../assets/* $(LIMBO_APP_X86)/assets/
	@echo
	@echo "installed lib$(QEMU_PROG_NAME).so for $(APP_ABI_DIR)"
	@$(READELF) -d $(LIMBO_APP_X86)/jniLibs/$(APP_ABI_DIR)/lib$(QEMU_PROG_NAME).so \
		| grep NEEDED || true
	@echo "(every NEEDED entry must be an unversioned platform library:"
	@echo " Android does not extract lib*.so.N from an APK)"

######################################################################
limbo: ndk deps config-qemu qemu install

clean: clean-qemu clean-ndk
distclean: clean clean-deps

help:
	@echo " Usage: export BUILD_HOST=<abi> && export BUILD_GUEST=<arch>-softmmu && make limbo"
	@echo "  abi  (device):   arm64-v8a, x86_64      <- 64-bit only, see android-limbo-config.mak"
	@echo "  arch (emulator): x86_64, aarch64, ppc64, sparc64"
	@echo "  optional: export NDK_DEBUG=1 for debuggable binaries"
	@echo
	@echo " example: export BUILD_HOST=arm64-v8a BUILD_GUEST=x86_64-softmmu && make limbo"
	@echo
	@echo " targets: check-tools deps config-qemu qemu install clean distclean"
