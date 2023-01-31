# libguestfs
# Copyright (C) 2009-2020 Red Hat Inc.
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.

dnl Any C libraries required by the libguestfs C library (not the daemon).

dnl Of course we need libguestfs.
dnl
dnl We need libguestfs 1.49.8 for guestfs_inspect_get_build_id in
dnl virt-drivers.
PKG_CHECK_MODULES([LIBGUESTFS], [libguestfs >= 1.49.8])

dnl Test if it's GNU or XSI strerror_r.
AC_FUNC_STRERROR_R

dnl Define a C symbol for the host CPU architecture.
AC_DEFINE_UNQUOTED([host_cpu],["$host_cpu"],[Host architecture.])

dnl Headers.
AC_CHECK_HEADERS([\
    byteswap.h \
    endian.h \
    error.h \
    errno.h \
    linux/fs.h \
    linux/magic.h \
    linux/raid/md_u.h \
    linux/rtc.h \
    printf.h \
    sys/endian.h \
    sys/inotify.h \
    sys/mount.h \
    sys/resource.h \
    sys/socket.h \
    sys/statfs.h \
    sys/statvfs.h \
    sys/time.h \
    sys/types.h \
    sys/un.h \
    sys/vfs.h \
    sys/wait.h \
    windows.h \
    sys/xattr.h])

dnl Functions.
AC_CHECK_FUNCS([\
    be32toh \
    error \
    fsync \
    futimens \
    getprogname \
    getxattr \
    htonl \
    htons \
    inotify_init1 \
    lgetxattr \
    listxattr \
    llistxattr \
    lsetxattr \
    lremovexattr \
    mknod \
    ntohl \
    ntohs \
    posix_fallocate \
    posix_fadvise \
    removexattr \
    setitimer \
    setrlimit \
    setxattr \
    sigaction \
    statfs \
    statvfs \
    sync])

dnl Which header file defines major, minor, makedev.
AC_HEADER_MAJOR

dnl tgetent, tputs and UP [sic] are all required.  They come from the lower
dnl tinfo library, but might be part of ncurses directly.
PKG_CHECK_MODULES([LIBTINFO], [tinfo], [], [
    PKG_CHECK_MODULES([LIBTINFO], [ncurses], [], [
        AC_CHECK_PROGS([NCURSES_CONFIG], [ncurses6-config ncurses5-config], [no])
        AS_IF([test "x$NCURSES_CONFIG" = "xno"], [
            AC_MSG_ERROR([ncurses development package is not installed])
        ])
        LIBTINFO_CFLAGS=`$NCURSES_CONFIG --cflags`
        LIBTINFO_LIBS=`$NCURSES_CONFIG --libs`
    ])
])
AC_SUBST([LIBTINFO_CFLAGS])
AC_SUBST([LIBTINFO_LIBS])

dnl GNU gettext tools (optional).
AC_CHECK_PROG([XGETTEXT],[xgettext],[xgettext],[no])
AC_CHECK_PROG([MSGCAT],[msgcat],[msgcat],[no])
AC_CHECK_PROG([MSGFMT],[msgfmt],[msgfmt],[no])
AC_CHECK_PROG([MSGMERGE],[msgmerge],[msgmerge],[no])

dnl Check they are the GNU gettext tools.
AC_MSG_CHECKING([msgfmt is GNU tool])
if $MSGFMT --version >/dev/null 2>&1 && $MSGFMT --version | grep -q 'GNU gettext'; then
    msgfmt_is_gnu=yes
else
    msgfmt_is_gnu=no
fi
AC_MSG_RESULT([$msgfmt_is_gnu])
AM_CONDITIONAL([HAVE_GNU_GETTEXT],
    [test "x$XGETTEXT" != "xno" && test "x$MSGCAT" != "xno" && test "x$MSGFMT" != "xno" && test "x$MSGMERGE" != "xno" && test "x$msgfmt_is_gnu" != "xno"])

dnl Check for gettext.
AM_GNU_GETTEXT([external])

dnl Check for PCRE2 (required)
PKG_CHECK_MODULES([PCRE2], [libpcre2-8], [], [
    AC_CHECK_PROGS([PCRE2_CONFIG], [pcre2-config], [no])
    AS_IF([test "x$PCRE2_CONFIG" = "xno"], [
        AC_MSG_ERROR([Please install the pcre2 devel package])
    ])
    PCRE_CFLAGS=`$PCRE2_CONFIG --cflags`
    PCRE_LIBS=`$PCRE2_CONFIG --libs8`
])

dnl libvirt (highly recommended)
AC_ARG_WITH([libvirt],[
    AS_HELP_STRING([--without-libvirt],
                   [disable libvirt support @<:@default=check@:>@])],
    [],
    [with_libvirt=check])
AS_IF([test "$with_libvirt" != "no"],[
    PKG_CHECK_MODULES([LIBVIRT], [libvirt >= 0.10.2],[
        AC_SUBST([LIBVIRT_CFLAGS])
        AC_SUBST([LIBVIRT_LIBS])
        AC_DEFINE([HAVE_LIBVIRT],[1],[libvirt found at compile time.])
    ],[
        if test "$DEFAULT_BACKEND" = "libvirt"; then
            AC_MSG_ERROR([Please install the libvirt devel package])
        else
            AC_MSG_WARN([libvirt not found, some core features will be disabled])
        fi
    ])
])
AM_CONDITIONAL([HAVE_LIBVIRT],[test "x$LIBVIRT_LIBS" != "x"])

libvirt_ro_uri='qemu+unix:///system?socket=/var/run/libvirt/libvirt-sock-ro'
AC_SUBST([libvirt_ro_uri])

dnl libxml2 (required)
PKG_CHECK_MODULES([LIBXML2], [libxml-2.0])
old_LIBS="$LIBS"
LIBS="$LIBS $LIBXML2_LIBS"
AC_CHECK_FUNCS([xmlBufferDetach])
LIBS="$old_LIBS"

dnl Check for Jansson JSON library (required).
PKG_CHECK_MODULES([JANSSON], [jansson >= 2.7])

dnl Check for libosinfo (mandatory)
PKG_CHECK_MODULES([LIBOSINFO], [libosinfo-1.0])
