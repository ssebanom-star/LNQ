#ifndef LIMBO_COMPAT_H
#define LIMBO_COMPAT_H

#include <jni.h>
#include <pthread.h>

extern JavaVM *jvm;
extern jobject jobj;
extern jclass jcls;
extern pthread_mutex_t fd_lock;
extern const char * storage_base_dir;
extern const char * limbo_base_dir;

void set_jni(JNIEnv* env, jobject obj1, jclass jclass1, const char * storage_dir, const char * limbo_dir);

/* Not provided by bionic on LP64; QEMU's util/memalign.c needs it. */
void * valloc (size_t size);

/*
 * strchrnul() is declared by bionic's <string.h> from API 24 onwards, so the
 * old shim (and its __ANDROID_HAVE_STRCHRNUL__ guard) is gone. See
 * limbo_compat.c for why the emulation was unsafe on 64-bit.
 */


#endif
