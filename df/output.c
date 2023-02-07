/* virt-df
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
#include <string.h>
#include <inttypes.h>
#include <errno.h>
#include <libintl.h>
#include <math.h>

#ifdef HAVE_LIBVIRT
#include <libvirt/libvirt.h>
#include <libvirt/virterror.h>
#endif

#include "human.h"

#include "guestfs.h"
#include "options.h"
#include "virt-df.h"

static void write_csv_field (FILE *fp, const char *field);

void
print_title (void)
{
  const char *cols[6];

  cols[0] = _("VirtualMachine");
  cols[1] = _("Filesystem");
  if (!inodes) {
    if (!human)
      cols[2] = _("1K-blocks");
    else
      cols[2] = _("Size");
    cols[3] = _("Used");
    cols[4] = _("Available");
    cols[5] = _("Use%");
  } else {
    cols[2] = _("Inodes");
    cols[3] = _("IUsed");
    cols[4] = _("IFree");
    cols[5] = _("IUse%");
  }

  if (!csv) {
    /* ignore cols[0] in this mode */
    printf ("%-36s%10s %10s %10s %5s\n",
            cols[1], cols[2], cols[3], cols[4], cols[5]);
  }
  else {
    size_t i;

    for (i = 0; i < 6; ++i) {
      if (i > 0)
        putchar (',');
      write_csv_field (stdout, cols[i]);
    }
    putchar ('\n');
  }
}

/* scale (n, 4096, 1024) ==> n * 4
 * scale (n, 512, 1024)  ==> n / 2
 */
static uintmax_t
scale (uintmax_t n, uintmax_t from, uintmax_t to)
{
  if (from >= to) {
    uintmax_t multiplier = from / to;
    return n * multiplier;
  }
  else {
    uintmax_t divisor = to / from;
    return n / divisor;
  }
}

void
print_stat (FILE *fp,
            const char *name, const char *uuid_param,
            const char *dev_param,
            const struct guestfs_statvfs *stat)
{
  /* First two columns are always 'name' and 'dev', followed by four
   * other data columns.  In text mode the 'name' and 'dev' are
   * combined into a single 'name:dev' column.  In CSV mode they are
   * kept as two separate columns.  In UUID mode the name might be
   * replaced by 'uuid', if available.
   */
#define MAX_LEN (LONGEST_HUMAN_READABLE > 128 ? LONGEST_HUMAN_READABLE : 128)
  char buf[4][MAX_LEN];
  const char *cols[4];
  int64_t v;
  float percent;
  const int hopts =
    human_round_to_nearest|human_autoscale|human_base_1024|human_SI;
  size_t i, len;
  char *dev;

  /* Make a canonical name. */
  dev = guestfs_canonical_device_name (g, dev_param);
  if (!dev)
    exit (EXIT_FAILURE);

  if (!inodes) {                /* 1K blocks */
    if (!human) {
      v = scale (stat->blocks, stat->bsize, 1024);
      snprintf (buf[0], MAX_LEN, "%" PRIi64, v);
      cols[0] = buf[0];
      v = scale (stat->blocks - stat->bfree, stat->bsize, 1024);
      snprintf (buf[1], MAX_LEN, "%" PRIi64, v);
      cols[1] = buf[1];
      v = scale (stat->bavail, stat->bsize, 1024);
      snprintf (buf[2], MAX_LEN, "%" PRIi64, v);
      cols[2] = buf[2];
    } else {
      cols[0] =
        human_readable ((uintmax_t) stat->blocks, buf[0],
                        hopts, stat->bsize, 1);
      v = stat->blocks - stat->bfree;
      cols[1] =
        human_readable ((uintmax_t) v, buf[1], hopts, stat->bsize, 1);
      cols[2] =
        human_readable ((uintmax_t) stat->bavail, buf[2],
                        hopts, stat->bsize, 1);
    }

    if (stat->blocks != 0)
      percent = 100. - 100. * stat->bfree / stat->blocks;
    else
      percent = 0;
  }
  else {                        /* inodes */
    snprintf (buf[0], MAX_LEN, "%" PRIi64, stat->files);
    cols[0] = buf[0];
    snprintf (buf[1], MAX_LEN, "%" PRIi64, stat->files - stat->ffree);
    cols[1] = buf[1];
    snprintf (buf[2], MAX_LEN, "%" PRIi64, stat->ffree);
    cols[2] = buf[2];

    if (stat->files != 0)
      percent = 100. - 100. * stat->ffree / stat->files;
    else
      percent = 0;
  }

  if (!csv)
    /* Use 'ceil' on the percentage in order to emulate what df itself does. */
    snprintf (buf[3], MAX_LEN, "%3.0f%%", ceil (percent));
  else
    snprintf (buf[3], MAX_LEN, "%.1f", (double) percent);
  cols[3] = buf[3];

#undef MAX_LEN

  if (uuid && uuid_param)
    name = uuid_param;

  if (!csv) {
    len = strlen (name) + strlen (dev) + 1;
    fprintf (fp, "%s:%s", name, dev);
    if (len <= 36) {
      for (i = len; i < 36; ++i)
        fputc (' ', fp);
    } else {
      fprintf (fp, "\n                                    ");
    }

    fprintf (fp, "%10s %10s %10s %5s\n", cols[0], cols[1], cols[2], cols[3]);
  }
  else {
    write_csv_field (fp, name);
    fputc (',', fp);
    write_csv_field (fp, dev);

    for (i = 0; i < 4; ++i) {
      fputc (',', fp);
      write_csv_field (fp, cols[i]);
    }

    fputc ('\n', fp);
  }

  free (dev);
}

/* Function to quote CSV fields on output without requiring an
 * external module.
 */
static void
write_csv_field (FILE *fp, const char *field)
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
    fprintf (fp, "%s", field);
    return;
  }

  /* Quoting for CSV fields. */
  fputc ('"', fp);
  for (i = 0; i < len; ++i) {
    if (field[i] == '"') {
      fputc ('"', fp);
      fputc ('"', fp);
    } else
      fputc (field[i], fp);
  }
  fputc ('"', fp);
}
