LOCAL_PATH:= $(call my-dir)

include $(CLEAR_VARS)

LOCAL_ARM_MODE:= $(APP_ARM_MODE)

LOCAL_SRC_FILES :=			\
	vm-executor-jni.c

LOCAL_MODULE := limbo

# The JNI bridge talks to QEMU purely through dlopen()/dlsym(), so it needs no
# QEMU or glib headers -- the old include paths into jni/qemu and jni/glib are
# gone along with those in-tree source directories.
LOCAL_C_INCLUDES :=			\
	$(LOCAL_PATH)/.. \
	$(LIMBO_JNI_ROOT)/compat

LOCAL_LDLIBS := -ldl -llog

LOCAL_CFLAGS += -include $(LOGUTILS)
LOCAL_CFLAGS += -Wno-format-security -Wno-macro-redefined

LOCAL_ARM_MODE := $(ARM_MODE)

LOCAL_SHARED_LIBRARIES := compat-limbo

include $(BUILD_SHARED_LIBRARY)
