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

/*
 * Linker-level interception of QEMU's file syscalls.
 *
 * Limbo lets the user pick disk images through the Android Storage Access
 * Framework, which hands back a "/content/..." URI rather than a real path.
 * QEMU knows nothing about that, so its open()/fopen()/stat() calls have to be
 * routed through the helpers in limbo_compat_filesystem.c, which ask the Java
 * layer for a file descriptor.
 *
 * Up to QEMU 5.1 this was done by rewriting the static archives after the
 * fact:
 *
 *     llvm-objcopy --redefine-sym open=android_open ... libqemu-system-*.a
 *
 * which was possible because Limbo drove the link itself from a rule injected
 * into QEMU's Makefile.target. QEMU 5.2 replaced that build system with meson,
 * and a ninja build offers no equivalent "rewrite the archive before linking"
 * hook. So the interception now happens at link time instead:
 *
 *     -Wl,--wrap=open -Wl,--wrap=fopen ...
 *
 * The linker redirects every reference to open() coming from the objects being
 * linked into libqemu-system-*.so to __wrap_open() instead. See
 * LIMBO_WRAP_SYMS in android-config/android-qemu-config.mak.
 *
 * Note on __real_*: those aliases only exist inside the link that passed
 * --wrap, which is the QEMU link, not this library's. That is fine -- this
 * file is compiled into libcompat-limbo.so, which is linked without --wrap, so
 * the plain calls to open()/close() below already reach libc directly and
 * there is no recursion.
 */

#include <errno.h>
#include <fcntl.h>
#include <pthread.h>
#include <stdarg.h>
#include <stdio.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

#include "limbo_compat_filesystem.h"
#include "limbo_logutils.h"

#define SAF_PREFIX "/content/"
#define SAF_PREFIX_LEN 9

static int limbo_is_saf_path(const char *path)
{
    return path != NULL && strncmp(path, SAF_PREFIX, SAF_PREFIX_LEN) == 0;
}

/*
 * Registry of descriptors that came from the Storage Access Framework.
 *
 * This exists because android_close() is expensive: it spawns a thread and
 * makes a JNI round trip into Java so the ParcelFileDescriptor can be closed
 * on the other side. QEMU closes a great many ordinary descriptors -- sockets,
 * pipes, timerfds, block backing files -- and sending all of them through that
 * path would be both slow and wrong.
 *
 * The old objcopy-based interception did exactly that, because a symbol
 * rename cannot discriminate. Doing the redirection in a real function lets us
 * only take the expensive route for descriptors we actually got from Java.
 *
 * A handful of disk images is the realistic maximum, so a small flat array
 * under a mutex is plenty; lookups happen once per close().
 */
#define LIMBO_MAX_SAF_FDS 64

static pthread_mutex_t saf_fds_lock = PTHREAD_MUTEX_INITIALIZER;
static int saf_fds[LIMBO_MAX_SAF_FDS];
static int saf_fds_count;

static void limbo_saf_fd_register(int fd)
{
    if (fd < 0) {
        return;
    }
    pthread_mutex_lock(&saf_fds_lock);
    if (saf_fds_count < LIMBO_MAX_SAF_FDS) {
        saf_fds[saf_fds_count++] = fd;
    } else {
        LOGW("SAF descriptor table full (%d), fd %d will be closed directly",
             LIMBO_MAX_SAF_FDS, fd);
    }
    pthread_mutex_unlock(&saf_fds_lock);
}

/* Returns 1 and removes the entry if fd came from the SAF, 0 otherwise. */
static int limbo_saf_fd_take(int fd)
{
    int found = 0;

    pthread_mutex_lock(&saf_fds_lock);
    for (int i = 0; i < saf_fds_count; i++) {
        if (saf_fds[i] == fd) {
            saf_fds[i] = saf_fds[--saf_fds_count];
            found = 1;
            break;
        }
    }
    pthread_mutex_unlock(&saf_fds_lock);

    return found;
}

int __wrap_open(const char *path, int flags, ...)
{
    int mode = 0;
    int fd;

    if (flags & O_CREAT) {
        va_list ap;
        va_start(ap, flags);
        mode = va_arg(ap, int);
        va_end(ap);
    }

    fd = android_open(path, flags, mode);

    if (limbo_is_saf_path(path)) {
        limbo_saf_fd_register(fd);
    }

    return fd;
}

/*
 * _FORTIFY_SOURCE rewrites open() with a known-constant flags argument into
 * __open_2(), so that entry point has to be intercepted as well or those call
 * sites would slip past. It has no variadic mode argument by construction:
 * bionic only emits it when O_CREAT is absent.
 */
int __wrap___open_2(const char *path, int flags)
{
    int fd = android_open(path, flags, 0);

    if (limbo_is_saf_path(path)) {
        limbo_saf_fd_register(fd);
    }

    return fd;
}

FILE *__wrap_fopen(const char *path, const char *mode)
{
    return android_fopen(path, mode);
}

int __wrap_close(int fd)
{
    if (limbo_saf_fd_take(fd)) {
        return android_close(fd);
    }

    return close(fd);
}

int __wrap_stat(const char *path, struct stat *buf)
{
    return android_stat(path, buf);
}

int __wrap_mkstemp(char *template_path)
{
    return android_mkstemp(template_path);
}
