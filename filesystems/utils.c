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

#include <config.h>

#include "guestfs.h"

#include "guestfs-utils.h"
#include "utils.h"

const char *
get_filesystem_version (guestfs_h *g, const char *dev, const char *fs_type)
{
  const char *version = NULL;

#ifdef GUESTFS_HAVE_XFS_INFO2
  /* For type=xfs, try to guess the filesystem version. */
  if (STREQ (fs_type, "xfs")) {
    CLEANUP_FREE_STRING_LIST char **hash = NULL;
    size_t i;

    guestfs_push_error_handler (g, NULL, NULL);

    hash = guestfs_xfs_info2 (g, dev);
    if (hash) {
      for (i = 0; hash[i] != NULL; i += 2) {
        if (STREQ (hash[i], "meta-data.crc")) {
          if (STREQ (hash[i+1], "0"))
            version = "4";
          else if (STREQ (hash[i+1], "1"))
            version = "5";
          break;
        }
        /* If new XFS versions are added in future then we can test
         * for new fields here ...
         */
      }
    }

    guestfs_pop_error_handler (g);
  }
#endif /* GUESTFS_HAVE_XFS_INFO2 */

  return version;
}
