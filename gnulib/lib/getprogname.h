/* libguestfs
 * Copyright (C) 2013-2023 Red Hat Inc.
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 2 of the License, or (at your option) any later version.
 *
 * This library is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public
 * License along with this library; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA
 */

#ifndef GUESTFS_GETPROGNAME
#define GUESTFS_GETPROGNAME

#ifndef HAVE_GETPROGNAME

#include <errno.h>

static inline char const *
getprogname (void)
{
  return program_invocation_short_name;
}

#endif

#endif /* GUESTFS_GETPROGNAME */
