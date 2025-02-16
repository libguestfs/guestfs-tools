/* virt-df
 * Copyright (C) 2010-2025 Red Hat Inc.
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
#include <unistd.h>
#include <getopt.h>
#include <errno.h>
#include <error.h>
#include <limits.h>
#include <locale.h>
#include <assert.h>
#include <libintl.h>

#ifdef HAVE_LIBVIRT
#include <libvirt/libvirt.h>
#include <libvirt/virterror.h>
#endif

#include "getprogname.h"

#include "guestfs.h"
#include "options.h"
#include "display-options.h"
#include "domains.h"
#include "parallel.h"
#include "virt-df.h"

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

int csv = 0;                    /* --csv */
int human = 0;                  /* --human-readable|-h */
int inodes = 0;                 /* --inodes */
int uuid = 0;                   /* --uuid */

static char *make_display_name (struct drv *drvs);

static void __attribute__((noreturn))
usage (int status)
{
  if (status != EXIT_SUCCESS)
    fprintf (stderr, _("Try ‘%s --help’ for more information.\n"),
             getprogname ());
  else {
    printf (_("%s: display free space on virtual filesystems\n"
              "Copyright (C) 2010 Red Hat Inc.\n"
              "Usage:\n"
              "  %s [--options] -d domname\n"
              "  %s [--options] -a disk.img [-a disk.img ...]\n"
              "Options:\n"
              "  -a|--add image       Add image\n"
              "  --blocksize[=512|4096]\n"
              "                       Set sector size of the disk for -a option\n"
              "  -c|--connect uri     Specify libvirt URI for -d option\n"
              "  --csv                Output as Comma-Separated Values\n"
              "  -d|--domain guest    Add disks from libvirt guest\n"
              "  --format[=raw|..]    Force disk format for -a option\n"
              "  -h|--human-readable  Print sizes in human-readable format\n"
              "  --help               Display brief help\n"
              "  -i|--inodes          Display inodes\n"
              "  --one-per-guest      Separate appliance per guest\n"
              "  -P nr_threads        Use at most nr_threads\n"
              "  --uuid               Print UUIDs instead of names\n"
              "  -v|--verbose         Verbose messages\n"
              "  -V|--version         Display version and exit\n"
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

  static const char options[] = "a:c:d:hiP:vVx";
  static const struct option long_options[] = {
    { "add", 1, 0, 'a' },
    { "blocksize", 2, 0, 0 },
    { "connect", 1, 0, 'c' },
    { "csv", 0, 0, 0 },
    { "domain", 1, 0, 'd' },
    { "format", 2, 0, 0 },
    { "help", 0, 0, HELP_OPTION },
    { "human-readable", 0, 0, 'h' },
    { "inodes", 0, 0, 'i' },
    { "long-options", 0, 0, 0 },
    { "one-per-guest", 0, 0, 0 },
    { "short-options", 0, 0, 0 },
    { "uuid", 0, 0, 0 },
    { "verbose", 0, 0, 'v' },
    { "version", 0, 0, 'V' },
    { 0, 0, 0, 0 }
  };
  struct drv *drvs = NULL;
  struct drv *drv;
  const char *format = NULL;
  bool format_consumed = true;
  int blocksize = 0;
  bool blocksize_consumed = true;
  int c;
  int option_index;
  size_t max_threads = 0;
  int err = 0;

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
      else if (STREQ (long_options[option_index].name, "format")) {
        OPTION_format;
      } else if (STREQ (long_options[option_index].name, "blocksize")) {
        OPTION_blocksize;
      } else if (STREQ (long_options[option_index].name, "csv")) {
        csv = 1;
      } else if (STREQ (long_options[option_index].name, "one-per-guest")) {
        /* nothing - left for backwards compatibility */
      } else if (STREQ (long_options[option_index].name, "uuid")) {
        uuid = 1;
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

    case 'i':
      inodes = 1;
      break;

    case 'P':
      if (sscanf (optarg, "%zu", &max_threads) != 1)
        error (EXIT_FAILURE, 0, _("-P option is not numeric"));
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

  /* Old-style syntax?  There were no -a or -d options in the old
   * virt-df which is how we detect this.
   */
  if (drvs == NULL) {
    while (optind < argc) {
      if (strchr (argv[optind], '/') ||
          access (argv[optind], F_OK) == 0) { /* simulate -a option */
        drv = calloc (1, sizeof (struct drv));
        if (!drv)
          error (EXIT_FAILURE, errno, "calloc");
        drv->type = drv_a;
        drv->a.filename = strdup (argv[optind]);
        if (!drv->a.filename)
          error (EXIT_FAILURE, errno, "strdup");
        drv->next = drvs;
        drvs = drv;
      } else {                  /* simulate -d option */
        drv = calloc (1, sizeof (struct drv));
        if (!drv)
          error (EXIT_FAILURE, errno, "calloc");
        drv->type = drv_d;
        drv->d.guest = argv[optind];
        drv->next = drvs;
        drvs = drv;
      }

      optind++;
    }
  }

  /* These are really constants, but they have to be variables for the
   * options parsing code.  Assert here that they have known-good
   * values.
   */
  assert (read_only == 1);
  assert (inspector == 0);

  /* Must be no extra arguments on the command line. */
  if (optind != argc)
    usage (EXIT_FAILURE);

  CHECK_OPTION_format_consumed;
  CHECK_OPTION_blocksize_consumed;

  /* -h and --csv doesn't make sense.  Spreadsheets will corrupt these
   * fields.  (RHBZ#600977).
   */
  if (human && csv)
    error (EXIT_FAILURE, 0, _("you cannot use -h and --csv options together."));

  /* virt-df has two modes.  If the user didn't specify any drives,
   * then we do the df on every libvirt guest.  That's the if-clause
   * below.  If the user specified domains/drives, then we assume they
   * belong to a single guest.  That's the else-clause below.
   */
  if (drvs == NULL) {
#if defined(HAVE_LIBVIRT)
    get_all_libvirt_domains (libvirt_uri);
    print_title ();
    err = start_threads (max_threads, g, df_work);
    free_domains ();
#else
    error (EXIT_FAILURE, 0,
           _("compiled without support for libvirt."));
#endif
  }
  else {                        /* Single guest. */
    CLEANUP_FREE char *name = NULL;

    /* Add domains/drives from the command line (for a single guest). */
    add_drives (drvs);

    if (guestfs_launch (g) == -1)
      exit (EXIT_FAILURE);

    print_title ();

    /* Synthesize a display name. */
    name = make_display_name (drvs);

    /* XXX regression: in the Perl version we cached the UUID from the
     * libvirt domain handle so it was available to us here.  In this
     * version the libvirt domain handle is hidden inside
     * guestfs_add_domain so the UUID is not available easily for
     * single '-d' command-line options.
     */
    err = df_on_handle (g, name, NULL, stdout);

    /* Free up data structures, no longer needed after this point. */
    free_drives (drvs);
  }

  guestfs_close (g);

  exit (err == 0 ? EXIT_SUCCESS : EXIT_FAILURE);
}

#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wanalyzer-null-argument"
/* Generate a display name for the single guest mode.  See comments in
 * https://bugzilla.redhat.com/show_bug.cgi?id=880801
 */
static char *
single_drive_display_name (struct drv *drvs)
{
  char *name = NULL;
  char *p;

  assert (drvs != NULL);
  assert (drvs->next == NULL);

  switch (drvs->type) {
  case drv_a:
    name = strrchr (drvs->a.filename, '/');
    if (name == NULL)
      name = drvs->a.filename;
    else
      name++;                   /* skip '/' character */
    name = strdup (name);
    if (name == NULL)
      error (EXIT_FAILURE, errno, "strdup");
    break;

  case drv_uri:
    name = strdup (drvs->uri.orig_uri);
    if (name == NULL)
      error (EXIT_FAILURE, errno, "strdup");
    /* Try to shorten the URI to just the final element, if it will
     * still make sense.
     */
    p = strrchr (name, '/');
    if (p && strlen (p) > 1) {
      p = strdup (p+1);
      if (!p)
        error (EXIT_FAILURE, errno, "strdup");
      free (name);
      name = p;
    }
    break;

  case drv_d:
    name = strdup (drvs->d.guest);
    if (name == NULL)
      error (EXIT_FAILURE, errno, "strdup");
    break;

  case drv_N:
  case drv_scratch:
    abort (); /* Only used in guestfish or virt-rescue. */
  }

  if (!name)
    abort ();

  return name;
}
#pragma GCC diagnostic pop

static char *
make_display_name (struct drv *drvs)
{
  char *ret;

  assert (drvs != NULL);

  /* Single disk or domain. */
  if (drvs->next == NULL)
    ret = single_drive_display_name (drvs);

  /* Multiple disks.  Multiple domains are possible, although that is
   * probably user error.  Choose the first name (last in the list),
   * and add '+' for each additional disk.
   */
  else {
    size_t pluses = 0;
    size_t i, len;

    while (drvs->next != NULL) {
      drvs = drvs->next;
      pluses++;
    }

    ret = single_drive_display_name (drvs);
    len = strlen (ret);

    ret = realloc (ret, len + pluses + 1);
    if (ret == NULL)
      error (EXIT_FAILURE, errno, "realloc");
    for (i = len; i < len + pluses; ++i)
      ret[i] = '+';
    ret[i] = '\0';
  }

  return ret;
}
