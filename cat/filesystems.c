/* virt-filesystems
 * Copyright (C) 2010-2023 Red Hat Inc.
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

#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <inttypes.h>
#include <unistd.h>
#include <getopt.h>
#include <errno.h>
#include <error.h>
#include <locale.h>
#include <assert.h>
#include <string.h>
#include <libintl.h>

#include "c-ctype.h"
#include "human.h"
#include "getprogname.h"

#include "guestfs.h"
#include "structs-cleanups.h"
#include "options.h"
#include "display-options.h"

/* These globals are shared with options.c. */
guestfs_h *g;

int read_only = 1;
int verbose = 0;
int keys_from_stdin = 0;
int echo_keys = 0;
const char *libvirt_uri = NULL;
int inspector = 0;
int in_guestfish = 0;
int in_virt_rescue = 0;

static int csv = 0;             /* --csv */
static int human = 0;           /* --human-readable|-h */

/* What is selected for output. */
#define OUTPUT_FILESYSTEMS        1
#define OUTPUT_FILESYSTEMS_EXTRA  2
#define OUTPUT_PARTITIONS         4
#define OUTPUT_BLOCKDEVS          8
#define OUTPUT_LVS               16
#define OUTPUT_VGS               32
#define OUTPUT_PVS               64
#define OUTPUT_ALL          INT_MAX
static int output = 0;

/* What columns to output.  This is in display order. */
#define COLUMN_NAME               1 /* always shown */
#define COLUMN_TYPE               2
#define COLUMN_VFS_TYPE           4 /* if --filesystems */
#define COLUMN_VFS_LABEL          8 /* if --filesystems */
#define COLUMN_MBR               16
#define COLUMN_SIZE              32 /* bytes, or human-readable if -h */
#define COLUMN_PARENTS           64
#define COLUMN_UUID             128 /* if --uuid */
#define NR_COLUMNS                8
static int columns;

static void do_output_title (void);
static void do_output (void);
static void do_output_end (void);

static struct guestfs_lvm_pv_list *get_pvs (void);
static void free_pvs (void);

static void __attribute__((noreturn))
usage (int status)
{
  if (status != EXIT_SUCCESS)
    fprintf (stderr, _("Try ‘%s --help’ for more information.\n"),
             getprogname ());
  else {
    printf (_("%s: list filesystems, partitions, block devices, LVM in a VM\n"
              "Copyright (C) 2010 Red Hat Inc.\n"
              "Usage:\n"
              "  %s [--options] -d domname\n"
              "  %s [--options] -a disk.img [-a disk.img ...]\n"
              "Options:\n"
              "  -a|--add image       Add image\n"
              "  --all                Display everything\n"
              "  --blkdevs|--block-devices\n"
              "                       Display block devices\n"
              "  --blocksize[=512|4096]\n"
              "                       Set sector size of the disk for -a option\n"
              "  -c|--connect uri     Specify libvirt URI for -d option\n"
              "  --csv                Output as Comma-Separated Values\n"
              "  -d|--domain guest    Add disks from libvirt guest\n"
              "  --echo-keys          Don't turn off echo for passphrases\n"
              "  --extra              Display swap and data filesystems\n"
              "  --filesystems        Display mountable filesystems\n"
              "  --format[=raw|..]    Force disk format for -a option\n"
              "  -h|--human-readable  Human-readable sizes in --long output\n"
              "  --help               Display brief help\n"
              "  --keys-from-stdin    Read passphrases from stdin\n"
              "  -l|--long            Long output\n"
              "  --lvs|--logvols|--logical-volumes\n"
              "                       Display LVM logical volumes\n"
              "  --no-title           No title in --long output\n"
              "  --parts|--partitions Display partitions\n"
              "  --pvs|--physvols|--physical-volumes\n"
              "                       Display LVM physical volumes\n"
              "  --uuid|--uuids       Add UUIDs to --long output\n"
              "  -v|--verbose         Verbose messages\n"
              "  -V|--version         Display version and exit\n"
              "  --vgs|--volgroups|--volume-groups\n"
              "                       Display LVM volume groups\n"
              "  -x                   Trace libguestfs API calls\n"
              "For more information, see the manpage %s(1).\n"),
            getprogname (), getprogname (),
            getprogname (), getprogname ());
  }
  exit (status);
}

int
main (int argc, char *argv[])
{
  setlocale (LC_ALL, "");
  bindtextdomain (PACKAGE, LOCALEBASEDIR);
  textdomain (PACKAGE);

  enum { HELP_OPTION = CHAR_MAX + 1 };

  static const char options[] = "a:c:d:hlvVx";
  static const struct option long_options[] = {
    { "add", 1, 0, 'a' },
    { "all", 0, 0, 0 },
    { "blkdevs", 0, 0, 0 },
    { "block-devices", 0, 0, 0 },
    { "blocksize", 2, 0, 0 },
    { "connect", 1, 0, 'c' },
    { "csv", 0, 0, 0 },
    { "domain", 1, 0, 'd' },
    { "echo-keys", 0, 0, 0 },
    { "extra", 0, 0, 0 },
    { "filesystems", 0, 0, 0 },
    { "format", 2, 0, 0 },
    { "help", 0, 0, HELP_OPTION },
    { "human-readable", 0, 0, 'h' },
    { "keys-from-stdin", 0, 0, 0 },
    { "logical-volumes", 0, 0, 0 },
    { "logvols", 0, 0, 0 },
    { "long", 0, 0, 'l' },
    { "long-options", 0, 0, 0 },
    { "lvs", 0, 0, 0 },
    { "no-title", 0, 0, 0 },
    { "parts", 0, 0, 0 },
    { "partitions", 0, 0, 0 },
    { "physical-volumes", 0, 0, 0 },
    { "physvols", 0, 0, 0 },
    { "pvs", 0, 0, 0 },
    { "short-options", 0, 0, 0 },
    { "uuid", 0, 0, 0 },
    { "uuids", 0, 0, 0 },
    { "verbose", 0, 0, 'v' },
    { "version", 0, 0, 'V' },
    { "vgs", 0, 0, 0 },
    { "volgroups", 0, 0, 0 },
    { "volume-groups", 0, 0, 0 },
    { 0, 0, 0, 0 }
  };
  struct drv *drvs = NULL;
  const char *format = NULL;
  bool format_consumed = true;
  int blocksize = 0;
  bool blocksize_consumed = true;
  int c;
  int option_index;
  int no_title = 0;             /* --no-title */
  int long_mode = 0;            /* --long|-l */
  int uuid = 0;                 /* --uuid */
  int title;

  g = guestfs_create ();
  if (g == NULL)
    error (EXIT_FAILURE, errno, "guestfs_create");

  for (;;) {
    c = getopt_long (argc, argv, options, long_options, &option_index);
    if (c == -1) break;

    switch (c) {
    case 0:			/* options which are long only */
      if (STREQ (long_options[option_index].name, "long-options"))
        display_long_options (long_options);
      else if (STREQ (long_options[option_index].name, "short-options"))
        display_short_options (options);
      else if (STREQ (long_options[option_index].name, "keys-from-stdin")) {
        keys_from_stdin = 1;
      } else if (STREQ (long_options[option_index].name, "echo-keys")) {
        echo_keys = 1;
      } else if (STREQ (long_options[option_index].name, "format")) {
        OPTION_format;
      } else if (STREQ (long_options[option_index].name, "blocksize")) {
        OPTION_blocksize;
      } else if (STREQ (long_options[option_index].name, "all")) {
        output = OUTPUT_ALL;
      } else if (STREQ (long_options[option_index].name, "blkdevs") ||
                 STREQ (long_options[option_index].name, "block-devices")) {
        output |= OUTPUT_BLOCKDEVS;
      } else if (STREQ (long_options[option_index].name, "csv")) {
        csv = 1;
      } else if (STREQ (long_options[option_index].name, "extra")) {
        output |= OUTPUT_FILESYSTEMS;
        output |= OUTPUT_FILESYSTEMS_EXTRA;
      } else if (STREQ (long_options[option_index].name, "filesystems")) {
        output |= OUTPUT_FILESYSTEMS;
      } else if (STREQ (long_options[option_index].name, "logical-volumes") ||
                 STREQ (long_options[option_index].name, "logvols") ||
                 STREQ (long_options[option_index].name, "lvs")) {
        output |= OUTPUT_LVS;
      } else if (STREQ (long_options[option_index].name, "no-title")) {
        no_title = 1;
      } else if (STREQ (long_options[option_index].name, "parts") ||
                 STREQ (long_options[option_index].name, "partitions")) {
        output |= OUTPUT_PARTITIONS;
      } else if (STREQ (long_options[option_index].name, "physical-volumes") ||
                 STREQ (long_options[option_index].name, "physvols") ||
                 STREQ (long_options[option_index].name, "pvs")) {
        output |= OUTPUT_PVS;
      } else if (STREQ (long_options[option_index].name, "uuid") ||
                 STREQ (long_options[option_index].name, "uuids")) {
        uuid = 1;
      } else if (STREQ (long_options[option_index].name, "vgs") ||
                 STREQ (long_options[option_index].name, "volgroups") ||
                 STREQ (long_options[option_index].name, "volume-groups")) {
        output |= OUTPUT_VGS;
      } else
        error (EXIT_FAILURE, 0,
               _("unknown long option: %s (%d)"),
               long_options[option_index].name, option_index);
      break;

    case 'a':
      OPTION_a;
      break;

    case 'c':
      OPTION_c;
      break;

    case 'd':
      OPTION_d;
      break;

    case 'h':
      human = 1;
      break;

    case 'l':
      long_mode = 1;
      break;

    case 'v':
      OPTION_v;
      break;

    case 'V':
      OPTION_V;
      break;

    case 'x':
      OPTION_x;
      break;

    case HELP_OPTION:
      usage (EXIT_SUCCESS);

    default:
      usage (EXIT_FAILURE);
    }
  }

  /* These are really constants, but they have to be variables for the
   * options parsing code.  Assert here that they have known-good
   * values.
   */
  assert (read_only == 1);
  assert (inspector == 0);

  /* Must be no extra arguments on the command line. */
  if (optind != argc) {
    fprintf (stderr, _("%s: error: extra argument ‘%s’ on command line.\n"
             "Make sure to specify the argument for --format "
             "like '--format=%s'.\n"),
             getprogname (), argv[optind], argv[optind]);
    usage (EXIT_FAILURE);
  }

  CHECK_OPTION_format_consumed;
  CHECK_OPTION_blocksize_consumed;

  /* -h and --csv doesn't make sense.  Spreadsheets will corrupt these
   * fields.  (RHBZ#600977).
   */
  if (human && csv)
    error (EXIT_FAILURE, 0,
           _("you cannot use -h and --csv options together."));

  /* Nothing selected for output, means --filesystems is implied. */
  if (output == 0)
    output = OUTPUT_FILESYSTEMS;

  /* What columns will be displayed? */
  columns = COLUMN_NAME;
  if (long_mode) {
    columns |= COLUMN_TYPE;
    columns |= COLUMN_SIZE;
    if ((output & OUTPUT_FILESYSTEMS)) {
      columns |= COLUMN_VFS_TYPE;
      columns |= COLUMN_VFS_LABEL;
    }
    columns |= COLUMN_PARENTS;
    if ((output & OUTPUT_PARTITIONS))
      columns |= COLUMN_MBR;
    if (uuid)
      columns |= COLUMN_UUID;
  }

  /* Display title by default only in long mode. */
  title = long_mode;
  if (no_title)
    title = 0;

  /* User must have specified some drives. */
  if (drvs == NULL) {
    fprintf (stderr, _("%s: error: you must specify at least one -a or -d option.\n"),
             getprogname ());
    usage (EXIT_FAILURE);
  }

  /* Add drives. */
  add_drives (drvs);

  if (guestfs_launch (g) == -1)
    exit (EXIT_FAILURE);

  /* Free up data structures, no longer needed after this point. */
  free_drives (drvs);

  if (title)
    do_output_title ();
  do_output ();
  do_output_end ();

  free_pvs ();

  guestfs_close (g);

  exit (EXIT_SUCCESS);
}

static void do_output_filesystems (void);
static void do_output_lvs (void);
static void do_output_vgs (void);
static void do_output_pvs (void);
static void do_output_partitions (void);
static void do_output_blockdevs (void);

static void write_row (const char *name, const char *type, const char *vfs_type, const char *vfs_label, int mbr_id, int64_t size, char **parents, const char *uuid);
static void write_row_strings (char **strings, size_t len);

static char **no_parents (void);
static int is_md (char *device);
static char **parents_of_md (char *device);
static char **parents_of_vg (char *vg);

static void
do_output_title (void)
{
  const char *headings[NR_COLUMNS];
  size_t len = 0;

  /* NB. These strings are not localized and must not contain spaces. */
  if ((columns & COLUMN_NAME))
    headings[len++] = "Name";
  if ((columns & COLUMN_TYPE))
    headings[len++] = "Type";
  if ((columns & COLUMN_VFS_TYPE))
    headings[len++] = "VFS";
  if ((columns & COLUMN_VFS_LABEL))
    headings[len++] = "Label";
  if ((columns & COLUMN_MBR))
    headings[len++] = "MBR";
  if ((columns & COLUMN_SIZE))
    headings[len++] = "Size";
  if ((columns & COLUMN_PARENTS))
    headings[len++] = "Parent";
  if ((columns & COLUMN_UUID))
    headings[len++] = "UUID";
  assert (len <= NR_COLUMNS);

  write_row_strings ((char **) headings, len);
}

static void
do_output (void)
{
  /* The ordering here is trying to be most specific -> least specific,
   * although that is not required or guaranteed.
   */
  if ((output & OUTPUT_FILESYSTEMS))
    do_output_filesystems ();

  if ((output & OUTPUT_LVS))
    do_output_lvs ();

  if ((output & OUTPUT_VGS))
    do_output_vgs ();

  if ((output & OUTPUT_PVS))
    do_output_pvs ();

  if ((output & OUTPUT_PARTITIONS))
    do_output_partitions ();

  if ((output & OUTPUT_BLOCKDEVS))
    do_output_blockdevs ();
}

static void
do_output_filesystems (void)
{
  size_t i;

  CLEANUP_FREE_STRING_LIST char **fses = guestfs_list_filesystems (g);
  if (fses == NULL)
    exit (EXIT_FAILURE);

  for (i = 0; fses[i] != NULL; i += 2) {
    CLEANUP_FREE char *dev = NULL, *vfs_label = NULL, *vfs_uuid = NULL;
    CLEANUP_FREE_STRING_LIST char **parents = NULL;
    int64_t size = -1;

    /* Skip swap and unknown, unless --extra flag was given. */
    if (!(output & OUTPUT_FILESYSTEMS_EXTRA) &&
        (STREQ (fses[i+1], "swap") || STREQ (fses[i+1], "unknown")))
      continue;

    dev = guestfs_canonical_device_name (g, fses[i]);
    if (dev == NULL)
      exit (EXIT_FAILURE);

    /* Only bother to look these up if we will be displaying them,
     * otherwise pass them as NULL.
     */
    if ((columns & COLUMN_VFS_LABEL)) {
      guestfs_push_error_handler (g, NULL, NULL);
      vfs_label = guestfs_vfs_label (g, fses[i]);
      guestfs_pop_error_handler (g);
      if (vfs_label == NULL) {
        vfs_label = strdup ("");
        if (!vfs_label)
          error (EXIT_FAILURE, errno, "strdup");
      }
    }
    if ((columns & COLUMN_UUID)) {
      guestfs_push_error_handler (g, NULL, NULL);
      vfs_uuid = guestfs_vfs_uuid (g, fses[i]);
      guestfs_pop_error_handler (g);
      if (vfs_uuid == NULL) {
        vfs_uuid = strdup ("");
        if (!vfs_uuid)
          error (EXIT_FAILURE, errno, "strdup");
      }
    }
    if ((columns & COLUMN_SIZE)) {
      CLEANUP_FREE char *device = guestfs_mountable_device (g, fses[i]);
      CLEANUP_FREE char *subvolume = NULL;

      guestfs_push_error_handler (g, NULL, NULL);

      subvolume = guestfs_mountable_subvolume (g, fses[i]);
      if (subvolume == NULL && guestfs_last_errno (g) != EINVAL) {
        fprintf (stderr,
                 _("%s: cannot determine the subvolume for %s: %s: %s\n"),
                getprogname (), fses[i],
                guestfs_last_error (g),
                strerror (guestfs_last_errno (g)));
        exit (EXIT_FAILURE);
      }

      guestfs_pop_error_handler (g);

      if (!device || !subvolume) {
        /* Try mounting and stating the device.  This might reasonably
         * fail, so don't show errors.
         */
        guestfs_push_error_handler (g, NULL, NULL);

        if (guestfs_mount_ro (g, fses[i], "/") == 0) {
          CLEANUP_FREE_STATVFS struct guestfs_statvfs *stat = NULL;

          stat = guestfs_statvfs (g, "/");
          size = stat->blocks * stat->bsize;
          guestfs_umount_all (g);
        } else {
          size = guestfs_blockdev_getsize64 (g, fses[i]);
        }

        guestfs_pop_error_handler (g);

        if (size == -1)
          exit (EXIT_FAILURE);
      }
    }

    if (is_md (fses[i]))
      parents = parents_of_md (fses[i]);
    else
      parents = no_parents ();

    write_row (dev, "filesystem",
               fses[i+1], vfs_label, -1, size, parents, vfs_uuid);
  }
}

static void
do_output_lvs (void)
{
  size_t i;

  CLEANUP_FREE_STRING_LIST char **lvs = guestfs_lvs (g);
  if (lvs == NULL)
    exit (EXIT_FAILURE);

  for (i = 0; lvs[i] != NULL; ++i) {
    CLEANUP_FREE char *uuid = NULL, *parent_name = NULL;
    const char *parents[2];
    int64_t size = -1;

    if ((columns & COLUMN_SIZE)) {
      size = guestfs_blockdev_getsize64 (g, lvs[i]);
      if (size == -1)
        exit (EXIT_FAILURE);
    }
    if ((columns & COLUMN_UUID)) {
      uuid = guestfs_lvuuid (g, lvs[i]);
      if (uuid == NULL)
        exit (EXIT_FAILURE);
    }
    if ((columns & COLUMN_PARENTS)) {
      parent_name = strdup (lvs[i]);
      if (parent_name == NULL)
        error (EXIT_FAILURE, errno, "strdup");
      char *p = strrchr (parent_name, '/');
      if (p)
        *p = '\0';
      parents[0] = parent_name;
      parents[1] = NULL;
    }

    write_row (lvs[i], "lv",
               NULL, NULL, -1, size, (char **) parents, uuid);
  }
}

static void
do_output_vgs (void)
{
  size_t i;

  CLEANUP_FREE_LVM_VG_LIST struct guestfs_lvm_vg_list *vgs =
    guestfs_vgs_full (g);
  if (vgs == NULL)
    exit (EXIT_FAILURE);

  for (i = 0; i < vgs->len; ++i) {
    CLEANUP_FREE char *name = NULL;
    char uuid[33];
    CLEANUP_FREE_STRING_LIST char **parents = NULL;

    if (asprintf (&name, "/dev/%s", vgs->val[i].vg_name) == -1)
      error (EXIT_FAILURE, errno, "asprintf");

    memcpy (uuid, vgs->val[i].vg_uuid, 32);
    uuid[32] = '\0';

    parents = parents_of_vg (vgs->val[i].vg_name);

    write_row (name, "vg",
               NULL, NULL, -1, (int64_t) vgs->val[i].vg_size, parents, uuid);
  }
}

/* Cache the output of guestfs_pvs_full, since we use it in a few places. */
static struct guestfs_lvm_pv_list *pvs_ = NULL;

static struct guestfs_lvm_pv_list *
get_pvs (void)
{
  if (pvs_)
    return pvs_;

  pvs_ = guestfs_pvs_full (g);
  if (pvs_ == NULL)
    exit (EXIT_FAILURE);

  return pvs_;
}

static void
free_pvs (void)
{
  if (pvs_)
    guestfs_free_lvm_pv_list (pvs_);

  pvs_ = NULL;
}

static void
do_output_pvs (void)
{
  size_t i;
  struct guestfs_lvm_pv_list *pvs = get_pvs ();

  for (i = 0; i < pvs->len; ++i) {
    char uuid[33];
    const char *parents[1] = { NULL };

    CLEANUP_FREE char *dev =
      guestfs_canonical_device_name (g, pvs->val[i].pv_name);
    if (!dev)
      exit (EXIT_FAILURE);

    memcpy (uuid, pvs->val[i].pv_uuid, 32);
    uuid[32] = '\0';
    write_row (dev, "pv",
               NULL, NULL, -1, (int64_t) pvs->val[i].pv_size,
               (char **) parents, uuid);
  }
}

static int
get_mbr_id (const char *dev, const char *parent_name)
{
  CLEANUP_FREE char *parttype = NULL;
  int mbr_id = -1, partnum;

  guestfs_push_error_handler (g, NULL, NULL);

  parttype = guestfs_part_get_parttype (g, parent_name);

  if (parttype && STREQ (parttype, "msdos")) {
    partnum = guestfs_part_to_partnum (g, dev);
    if (partnum >= 0)
      mbr_id = guestfs_part_get_mbr_id (g, parent_name, partnum);
  }

  guestfs_pop_error_handler (g);

  return mbr_id;
}

static void
do_output_partitions (void)
{
  size_t i;

  CLEANUP_FREE_STRING_LIST char **parts = guestfs_list_partitions (g);
  if (parts == NULL)
    exit (EXIT_FAILURE);

  for (i = 0; parts[i] != NULL; ++i) {
    CLEANUP_FREE char *dev = NULL, *parent_name = NULL, *canonical_name = NULL;
    const char *parents[2];
    int64_t size = -1;
    int mbr_id = -1;

    dev = guestfs_canonical_device_name (g, parts[i]);
    if (!dev)
      exit (EXIT_FAILURE);

    if ((columns & COLUMN_SIZE)) {
      size = guestfs_blockdev_getsize64 (g, parts[i]);
      if (size == -1)
        exit (EXIT_FAILURE);
    }
    if ((columns & COLUMN_PARENTS)) {
      parent_name = guestfs_part_to_dev (g, parts[i]);
      if (parent_name == NULL)
        exit (EXIT_FAILURE);

      if ((columns & COLUMN_MBR))
        mbr_id = get_mbr_id (parts[i], parent_name);

      canonical_name = guestfs_canonical_device_name (g, parent_name);
      if (!canonical_name)
        exit (EXIT_FAILURE);

      parents[0] = canonical_name;
      parents[1] = NULL;
    }

    write_row (dev, "partition",
               NULL, NULL, mbr_id, size, (char **) parents, NULL);
  }
}

static void
do_output_blockdevs (void)
{
  size_t i;

  CLEANUP_FREE_STRING_LIST char **devices = guestfs_list_devices (g);
  if (devices == NULL)
    exit (EXIT_FAILURE);

  for (i = 0; devices[i] != NULL; ++i) {
    int64_t size = -1;
    CLEANUP_FREE_STRING_LIST char **parents = NULL;
    CLEANUP_FREE char *dev = NULL;

    dev = guestfs_canonical_device_name (g, devices[i]);
    if (!dev)
      exit (EXIT_FAILURE);

    if ((columns & COLUMN_SIZE)) {
      size = guestfs_blockdev_getsize64 (g, devices[i]);
      if (size == -1)
        exit (EXIT_FAILURE);
    }

    if (is_md (devices[i]))
      parents = parents_of_md (devices[i]);
    else
      parents = no_parents ();

    write_row (dev, "device",
               NULL, NULL, -1, size, parents, NULL);
  }
}

/* Returns an empty list of parents.  Note this must be freed. */
static char **
no_parents (void)
{
  char **ret;

  ret = malloc (sizeof (char *));
  if (!ret)
    error (EXIT_FAILURE, errno, "malloc");

  ret[0] = NULL;

  return ret;
}

/* XXX Should be a better test than this. */
static int
is_md (char *device)
{
  char *p;

  if (!STRPREFIX (device, "/dev/md"))
    return 0;

  p = device + 7;
  while (*p) {
    if (!c_isdigit (*p))
      return 0;
    p++;
  }

  return 1;
}

static char **
parents_of_md (char *device)
{
  char **ret;
  size_t i;

  CLEANUP_FREE_MDSTAT_LIST struct guestfs_mdstat_list *stats =
    guestfs_md_stat (g, device);
  if (!stats)
    exit (EXIT_FAILURE);

  ret = malloc ((stats->len + 1) * sizeof (char *));
  if (!ret)
    error (EXIT_FAILURE, errno, "malloc");

  for (i = 0; i < stats->len; ++i) {
    ret[i] = guestfs_canonical_device_name (g, stats->val[i].mdstat_device);
    if (!ret[i])
      exit (EXIT_FAILURE);
  }

  ret[stats->len] = NULL;

  return ret;
}

/* Specialized PV UUID comparison function.
 * pvuuid1: from vgpvuuids, this may contain '-' characters which
 *   should be ignored.
 * pvuuid2: from pvs-full, this is 32 characters long and NOT
 *   terminated by \0
 */
static int
compare_pvuuids (const char *pvuuid1, const char *pvuuid2)
{
  size_t i;
  const char *p = pvuuid1;

  for (i = 0; i < 32; ++i) {
    while (*p && !c_isalnum (*p))
      p++;
    if (!*p)
      return 0;
    if (*p != pvuuid2[i])
      return 0;
  }

  return 1;
}

static char **
parents_of_vg (char *vg)
{
  struct guestfs_lvm_pv_list *pvs = get_pvs ();
  char **ret;
  size_t n, i, j;

  CLEANUP_FREE_STRING_LIST char **pvuuids = guestfs_vgpvuuids (g, vg);
  if (!pvuuids)
    exit (EXIT_FAILURE);

  n = guestfs_int_count_strings (pvuuids);

  ret = malloc ((n + 1) * sizeof (char *));
  if (!ret)
    error (EXIT_FAILURE, errno, "malloc");

  /* Resolve each PV UUID back to a PV. */
  for (i = 0; i < n; ++i) {
    for (j = 0; j < pvs->len; ++j) {
      if (compare_pvuuids (pvuuids[i], pvs->val[j].pv_uuid) == 0)
        break;
    }

    if (j < pvs->len) {
      ret[i] = guestfs_canonical_device_name (g, pvs->val[j].pv_name);
      if (!ret[i])
        exit (EXIT_FAILURE);
    }
    else {
      fprintf (stderr, "%s: warning: unknown PV UUID ignored\n", __func__);
      ret[i] = strndup (pvuuids[i], 32);
      if (!ret[i])
        error (EXIT_FAILURE, errno, "strndup");
    }
  }

  ret[i] = NULL;

  return ret;
}

static void
write_row (const char *name, const char *type,
           const char *vfs_type, const char *vfs_label, int mbr_id,
           int64_t size, char **parents, const char *uuid)
{
  const char *strings[NR_COLUMNS];
  CLEANUP_FREE char *parents_str = NULL;
  size_t len = 0;
  char hum[LONGEST_HUMAN_READABLE];
  char num[256];
  char mbr_id_str[32];

  if ((columns & COLUMN_NAME))
    strings[len++] = name;
  if ((columns & COLUMN_TYPE))
    strings[len++] = type;
  if ((columns & COLUMN_VFS_TYPE))
    strings[len++] = vfs_type;
  if ((columns & COLUMN_VFS_LABEL))
    strings[len++] = vfs_label;
  if ((columns & COLUMN_MBR)) {
    if (mbr_id >= 0) {
      snprintf (mbr_id_str, sizeof mbr_id_str, "%02x", (unsigned) mbr_id);
      strings[len++] = mbr_id_str;
    } else
      strings[len++] = NULL;
  }
  if ((columns & COLUMN_SIZE)) {
    if (size >= 0) {
      if (human) {
        strings[len++] =
          human_readable ((uintmax_t) size, hum,
                          human_round_to_nearest|human_autoscale|
                          human_base_1024|human_SI,
                          1, 1);
      }
      else {
        snprintf (num, sizeof num, "%" PRIi64, size);
        strings[len++] = num;
      }
    }
    else
      strings[len++] = NULL;
  }
  if ((columns & COLUMN_PARENTS)) {
    /* Internally comma-separated field. */
    parents_str = guestfs_int_join_strings (",", parents);
    strings[len++] = parents_str;
  }
  if ((columns & COLUMN_UUID))
    strings[len++] = uuid;
  assert (len <= NR_COLUMNS);

  write_row_strings ((char **) strings, len);
}

static void add_row (char **strings, size_t len);
static void write_csv_field (const char *field);

static void
write_row_strings (char **strings, size_t len)
{
  if (!csv) {
    /* Text mode.  Because we want the columns to line up, we can't
     * output directly, but instead need to save up the rows and
     * output them at the end.
     */
    add_row (strings, len);
  }
  else {                    /* CSV mode: output it directly, quoted */
    size_t i;

    for (i = 0; i < len; ++i) {
      if (i > 0)
        putchar (',');
      if (strings[i] != NULL)
        write_csv_field (strings[i]);
    }
    putchar ('\n');
  }
}

/* Function to quote CSV fields on output without requiring an
 * external module.
 */
static void
write_csv_field (const char *field)
{
  size_t i, len;
  int needs_quoting = 0;

  len = strlen (field);

  for (i = 0; i < len; ++i) {
    if (field[i] == ' ' || field[i] == '"' ||
        field[i] == '\n' || field[i] == ',') {
      needs_quoting = 1;
      break;
    }
  }

  if (!needs_quoting) {
    printf ("%s", field);
    return;
  }

  /* Quoting for CSV fields. */
  putchar ('"');
  for (i = 0; i < len; ++i) {
    if (field[i] == '"') {
      putchar ('"');
      putchar ('"');
    } else
      putchar (field[i]);
  }
  putchar ('"');
}

/* This code is only used in text mode (non-CSV output). */
static char ***rows = NULL;
static size_t nr_rows = 0;
static size_t max_width[NR_COLUMNS];

static void
add_row (char **strings, size_t len)
{
  size_t i, slen;
  char **row;

  assert (len <= NR_COLUMNS);

  row = malloc (sizeof (char *) * len);
  if (row == NULL)
    error (EXIT_FAILURE, errno, "malloc");

  for (i = 0; i < len; ++i) {
    if (strings[i]) {
      row[i] = strdup (strings[i]);
      if (row[i] == NULL)
        error (EXIT_FAILURE, errno, "strdup");

      /* Keep a running total of the max width of each column. */
      slen = strlen (strings[i]);
      if (slen == 0)
        slen = 1; /* because "" is printed as "-" */
      if (slen > max_width[i])
        max_width[i] = slen;
    }
    else
      row[i] = NULL;
  }

  rows = realloc (rows, sizeof (char **) * (nr_rows + 1));
  if (rows == NULL)
    error (EXIT_FAILURE, errno, "realloc");
  rows[nr_rows] = row;
  nr_rows++;
}

/* In text mode we saved up all the output so that we can print the
 * columns aligned.
 */
static void
do_output_end (void)
{
  size_t i, j, k, len, space_btwn;

  if (csv)
    return;

  /* How much space between columns?  Try 2 spaces between columns, but
   * if that just pushes us over 72 columns, use 1 space.
   */
  space_btwn = 2;
  i = 0;
  for (j = 0; j < NR_COLUMNS; ++j)
    i += max_width[j] + space_btwn;
  if (i > 72)
    space_btwn = 1;

  for (i = 0; i < nr_rows; ++i) {
    char **row = rows[i];

    k = 0;

    for (j = 0; j < NR_COLUMNS; ++j) {
      /* Ignore columns which are completely empty.  This also deals
       * with the fact that we didn't remember the length of each row
       * in add_row above.
       */
      if (max_width[j] == 0)
        continue;

      while (k) {
        putchar (' ');
        k--;
      }

      if (row[j] == NULL || STREQ (row[j], "")) {
        printf ("-");
        len = 1;
      } else {
        printf ("%s", row[j]);
        len = strlen (row[j]);
      }
      free (row[j]);

      assert (len <= max_width[j]);
      k = max_width[j] - len + space_btwn;
    }

    putchar ('\n');
    free (row);
  }
  free (rows);
}
