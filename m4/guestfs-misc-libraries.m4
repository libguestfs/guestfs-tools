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

dnl Miscellaneous libraries used by other programs.

dnl glibc 2.27 removes crypt(3) and suggests using libxcrypt.
PKG_CHECK_MODULES([LIBCRYPT], [libxcrypt], [
    AC_SUBST([LIBCRYPT_CFLAGS])
    AC_SUBST([LIBCRYPT_LIBS])
],[
    dnl Check if crypt() is provided by another library.
    old_LIBS="$LIBS"
    AC_SEARCH_LIBS([crypt],[crypt])
    LIBS="$old_LIBS"
    if test "$ac_cv_search_crypt" = "-lcrypt" ; then
        LIBCRYPT_LIBS="-lcrypt"
    fi
    AC_SUBST([LIBCRYPT_LIBS])
])

dnl Do we need to include <crypt.h>?
old_CFLAGS="$CFLAGS"
CFLAGS="$CFLAGS $LIBCRYPT_CFLAGS"
AC_CHECK_HEADERS([crypt.h])
CFLAGS="$old_CFLAGS"

dnl liblzma can be used by virt-builder (optional).
PKG_CHECK_MODULES([LIBLZMA], [liblzma], [
    AC_SUBST([LIBLZMA_CFLAGS])
    AC_SUBST([LIBLZMA_LIBS])
    AC_DEFINE([HAVE_LIBLZMA],[1],[liblzma found at compile time.])

    dnl Old lzma in RHEL 6 didn't have some APIs we need.
    old_LIBS="$LIBS"
    LIBS="$LIBS $LIBLZMA_LIBS"
    AC_CHECK_FUNCS([lzma_index_stream_flags lzma_index_stream_padding])
    LIBS="$old_LIBS"
],
[AC_MSG_WARN([liblzma not found, virt-builder will be slower])])
