/* Utility function used by virt-filesystems and virrt-inspector
 * Copyright (C) 2026 Red Hat Inc.
 *
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
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
 */

#ifndef GUESTFS_FILESYSTEMS_UTILS_H
#define GUESTFS_FILESYSTEMS_UTILS_H

#include "guestfs.h"

/* For XFS, return the filesystem version (eg. "4" or "5").  This may
 * return NULL if no filesystem version is known.
 */
const char *get_filesystem_version (guestfs_h *g,
                                    const char *dev, const char *fs_type);

#endif /* GUESTFS_FILESYSTEMS_UTILS_H */
