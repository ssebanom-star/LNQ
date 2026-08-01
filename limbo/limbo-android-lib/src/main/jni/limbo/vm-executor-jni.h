/*
 Copyright (C) Max Kastanas 2012

 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
 *
 */

#ifndef VM_EXECUTOR_JNI_H
#define VM_EXECUTOR_JNI_H

#include <jni.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>

/*
 * Shutdown reasons, mirroring the ShutdownCause enum in QEMU's
 * qapi/run-state.json. QEMU's own comment there warns that
 * shutdown_caused_by_guest() depends on the enumeration order, so these must
 * be re-checked whenever QEMU is upgraded.
 *
 * The emulator is dlopen()ed, so we cannot include QEMU's generated headers
 * and have to restate the values here.
 *
 * Verified against QEMU 11.0.3.
 */
typedef enum {
    LIMBO_SHUTDOWN_CAUSE_NONE = 0,
    LIMBO_SHUTDOWN_CAUSE_HOST_ERROR = 1,
    LIMBO_SHUTDOWN_CAUSE_HOST_QMP_QUIT = 2,
    LIMBO_SHUTDOWN_CAUSE_HOST_QMP_SYSTEM_RESET = 3,
    LIMBO_SHUTDOWN_CAUSE_HOST_SIGNAL = 4,
    LIMBO_SHUTDOWN_CAUSE_HOST_UI = 5,
    LIMBO_SHUTDOWN_CAUSE_GUEST_SHUTDOWN = 6,
    LIMBO_SHUTDOWN_CAUSE_GUEST_RESET = 7,
    LIMBO_SHUTDOWN_CAUSE_GUEST_PANIC = 8,
    LIMBO_SHUTDOWN_CAUSE_SUBSYSTEM_RESET = 9,
    LIMBO_SHUTDOWN_CAUSE_SNAPSHOT_LOAD = 10,
} LimboShutdownCause;


void * loadLib(const char* lib_filename, const char * lib_path_str);

void setup_jni(JNIEnv* env, jobject thiz, jstring storage_dir, jstring base_dir);

int get_qemu_var(JNIEnv* env, jobject thiz, const char * var);

void set_qemu_var(JNIEnv* env, jobject thiz, const char * var, jint jvalue);

JNIEXPORT void JNICALL Java_com_max2idea_android_limbo_jni_VMExecutor_nativeRefreshScreen(
                JNIEnv* env, jobject thiz, jint jvalue);
                
JNIEXPORT void JNICALL Java_com_max2idea_android_limbo_jni_VMExecutor_setvncrefreshrate(
		JNIEnv* env, jobject thiz, jint jvalue);

JNIEXPORT void JNICALL Java_com_max2idea_android_limbo_jni_VMExecutor_setSDLRefreshRateDefault(
		JNIEnv* env, jobject thiz, jint jvalue);
        
JNIEXPORT void JNICALL Java_com_max2idea_android_limbo_jni_VMExecutor_setSDLRefreshRateIdle(
		JNIEnv* env, jobject thiz, jint jvalue);
        
JNIEXPORT jint JNICALL Java_com_max2idea_android_limbo_jni_VMExecutor_getSDLRefreshRateDefault(
		JNIEnv* env, jobject thiz);
        
JNIEXPORT jint JNICALL Java_com_max2idea_android_limbo_jni_VMExecutor_getSDLRefreshRateIdle(
		JNIEnv* env, jobject thiz);

JNIEXPORT jint JNICALL Java_com_max2idea_android_limbo_jni_VMExecutor_getvncrefreshrate(
		JNIEnv* env, jobject thiz);

JNIEXPORT jstring JNICALL Java_com_max2idea_android_limbo_jni_VMExecutor_start(
        JNIEnv* env, jobject thiz,
		jstring storage_dir, jstring base_dir,
		jstring lib_filename, jstring lib_path,
		jint sdl_scale_hint,
		jobjectArray params);
        
JNIEXPORT jstring JNICALL Java_com_max2idea_android_limbo_jni_VMExecutor_stop(
		JNIEnv* env, jobject thiz, jint jint_restart);

#endif

