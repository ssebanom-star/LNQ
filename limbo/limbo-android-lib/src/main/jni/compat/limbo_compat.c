
#include <jni.h>
#include <malloc.h>
#include <string.h>
#include <unistd.h>
#include "limbo_logutils.h"
#include "limbo_compat.h"

JavaVM *jvm = NULL;
jobject jobj = NULL;
jclass jcls = NULL;
pthread_mutex_t fd_lock;
const char * storage_base_dir;
const char * limbo_base_dir;

void set_jni(JNIEnv* env, jobject obj1, jclass jclass1,
    const char * storage_dir, const char * base_dir) {
	if (pthread_mutex_init(&fd_lock, NULL) != 0) {
		LOGE("JNI Mutex init failed");
		return;
	}
	jint rs = (*env)->GetJavaVM(env, &jvm);
	jobj = (*env)->NewGlobalRef(env, obj1);
	jcls = (jclass) (*env)->NewGlobalRef(env, jclass1);
	limbo_base_dir = base_dir;
	storage_base_dir = storage_dir;
}

/*
 * bionic does not provide valloc() on 64-bit Android (it was dropped for LP64
 * along with pvalloc). QEMU's util/memalign.c has a valloc() branch, though on
 * Android it takes the posix_memalign() one instead, so this is kept as a
 * safety net for other callers rather than because QEMU needs it.
 *
 * <malloc.h> has to be included for memalign: without it clang treats the call
 * as an implicit declaration returning int, which on LP64 truncates the
 * returned pointer. NDK r27's clang rejects that outright rather than warning.
 */
void *
valloc (size_t size)
{
  return memalign (getpagesize (), size);
}

/*
 * strchrnul() used to be emulated here as well. That shim is gone: bionic has
 * provided strchrnul() since API 24 and this project targets 28, so the
 * emulation is dead code -- and it was wrong on 64-bit anyway. It computed the
 * end-of-string pointer as
 *
 *     int endofs = s + length;
 *     return endofs;
 *
 * which truncates a 64-bit pointer through an int. That went unnoticed while
 * Limbo only shipped 32-bit ABIs, where int and pointers happen to be the same
 * width; on arm64 it would have returned a garbage pointer.
 */
