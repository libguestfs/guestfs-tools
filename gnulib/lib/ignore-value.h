/* ignore a function return without a compiler warning.  -*- coding: utf-8 -*-

   Copyright (C) 2008-2025 Free Software Foundation, Inc.

   (NB: I modified the original GPL boilerplate here to LGPLv2+.  This
   is because of the weird way that gnulib uses licenses, where the
   real license is covered in the modules/X file.  The real license
   for this file is LGPLv2+, not GPL.  - RWMJ)

   This library is free software; you can redistribute it and/or
   modify it under the terms of the GNU Lesser General Public
   License as published by the Free Software Foundation; either
   version 2 of the License, or (at your option) any later version.

   This library is distributed in the hope that it will be useful,
   but WITHOUT ANY WARRANTY; without even the implied warranty of
   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
   Lesser General Public License for more details.

   You should have received a copy of the GNU Lesser General Public
   License along with this library; if not, write to the Free Software
   Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA
 */

/* Written by Jim Meyering, Eric Blake and Pádraig Brady.  */

/* Use "ignore_value" to avoid a warning when using a function declared with
   gcc's warn_unused_result attribute, but for which you really do want to
   ignore the result.  Traditionally, people have used a "(void)" cast to
   indicate that a function's return value is deliberately unused.  However,
   if the function is declared with __attribute__((warn_unused_result)),
   gcc issues a warning even with the cast.

   Caution: most of the time, you really should heed gcc's warning, and
   check the return value.  However, in those exceptional cases in which
   you're sure you know what you're doing, use this function.

   For the record, here's one of the ignorable warnings:
   "copy.c:233: warning: ignoring return value of 'fchown',
   declared with attribute warn_unused_result".  */

#ifndef _GL_IGNORE_VALUE_H
#define _GL_IGNORE_VALUE_H

/* Normally casting an expression to void discards its value, but GCC
   versions 3.4 and newer have __attribute__ ((__warn_unused_result__))
   which may cause unwanted diagnostics in that case.  Use __typeof__
   and __extension__ to work around the problem, if the workaround is
   known to be needed.
   The workaround is not needed with clang.  */
#if (3 < __GNUC__ + (4 <= __GNUC_MINOR__)) && !defined __clang__
# define ignore_value(x) \
    (__extension__ ({ __typeof__ (x) __x = (x); (void) __x; }))
#else
# define ignore_value(x) ((void) (x))
#endif

#endif
