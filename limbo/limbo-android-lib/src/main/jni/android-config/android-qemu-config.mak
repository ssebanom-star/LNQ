#### DO NOT CHANGE
#
# Assembles the ./configure command line for QEMU.
#
# Unlike the pre-5.2 versions of this file there is no "config:" target and no
# recipe that cds into ./qemu: QEMU 11 builds out of tree with meson, so the
# configure and build rules live in the top-level jni/Makefile and this file
# only defines variables.

QEMU_TARGET_LIST = $(BUILD_GUEST)
QEMU_CONFIG_DIR = $(LIMBO_JNI_ROOT)/android-config

ifeq ($(USE_QEMU_VERSION),11.0.3)
include $(QEMU_CONFIG_DIR)/android-qemu-config-11.0.3.mak
else
$(error Unsupported QEMU version = $(USE_QEMU_VERSION). \
  This tree targets 11.0.3; the 2.9.1 and 5.1.0 recipes were removed together \
  with the Makefile.target build hook they depended on.)
endif

######################################################################
# Android storage access
#
# Limbo opens disk images through the Storage Access Framework, so QEMU's
# file syscalls have to be routed through the JNI helpers in
# compat/limbo_compat_filesystem.c.
#
# The QEMU 5.1.0 build did this by rewriting the static archives after the
# fact with "llvm-objcopy --redefine-sym open=android_open". That hook lived
# in Makefile.target and there is no equivalent step in a meson/ninja build,
# so we let the linker do it instead: --wrap=open makes every reference to
# open() resolve to __wrap_open(), and the real one stays reachable as
# __real_open(). Same effect, no archive surgery, and it survives LTO.
######################################################################

LIMBO_WRAP_SYMS = open fopen close stat mkstemp __open_2

QEMU_WRAP_LDFLAGS = $(foreach s,$(LIMBO_WRAP_SYMS),-Wl,--wrap=$(s))

######################################################################
# Link flags
######################################################################

# Android 15 runs on devices with 16 KB pages; shared libraries have to be
# aligned accordingly or the loader rejects them.
QEMU_LDFLAGS += -Wl,-z,max-page-size=16384
QEMU_LDFLAGS += -Wl,-z,noexecstack -Wl,-z,relro -Wl,-z,now
QEMU_LDFLAGS += $(QEMU_WRAP_LDFLAGS)
QEMU_LDFLAGS += -L$(LIMBO_PREFIX_ABS)/lib
QEMU_LDFLAGS += -L$(NDK_PROJECT_PATH)/obj/local/$(APP_ABI)
QEMU_LDFLAGS += -lcompat-limbo -llog
QEMU_LDFLAGS += $(ARCH_LD_FLAGS)

# limbo_logutils.h (force-included into every QEMU translation unit by
# SYSTEM_INCLUDE) redefines printf/fprintf as macros that route output to
# logcat. That defeats clang's format-string literal analysis, and QEMU builds
# with -Werror, so the check has to be turned off or e.g. qemu-io-cmds.c fails
# with -Wformat-security.
QEMU_WARNING_FLAGS += -Wno-format-security
QEMU_WARNING_FLAGS += -Wno-macro-redefined
QEMU_WARNING_FLAGS += -Wno-unknown-warning-option

QEMU_CFLAGS += $(QEMU_WARNING_FLAGS)
QEMU_CFLAGS += $(SYSTEM_INCLUDE)
QEMU_CFLAGS += $(SDL_RENDERING)
QEMU_CFLAGS += $(ARCH_CFLAGS)

# Set SDL software rendering (works everywhere, slower)
#SDL_RENDERING = -D__LIMBO_SDL_FORCE_SOFTWARE_RENDERING__
# Or SDL hardware acceleration (faster, needs a whole screen redraw)
SDL_RENDERING = -D__LIMBO_SDL_FORCE_HARDWARE_RENDERING__

######################################################################
# The assembled configure command line
######################################################################

QEMU_CONFIGURE_FLAGS = \
	--target-list=$(QEMU_TARGET_LIST) \
	--cc=$(CC) \
	--cxx=$(CXX) \
	--cross-prefix=$(CROSS_PREFIX) \
	--cpu=$(MESON_CPU_FAMILY) \
	$(QEMU_FEATURES) \
	$(QEMU_DISABLE) \
	$(QEMU_DEBUG) \
	$(QEMU_LIMBO_OPTS) \
	--extra-cflags="$(QEMU_CFLAGS)" \
	--extra-ldflags="$(QEMU_LDFLAGS)"
