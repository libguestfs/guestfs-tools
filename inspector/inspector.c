/* virt-inspector
 * Copyright (C) 2010-2012 Red Hat Inc.
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
#include <string.h>
#include <inttypes.h>
#include <unistd.h>
#include <errno.h>
#include <error.h>
#include <getopt.h>
#include <locale.h>
#include <assert.h>
#include <libintl.h>

#include <libxml/xmlIO.h>
#include <libxml/xmlwriter.h>
#include <libxml/xpath.h>
#include <libxml/parser.h>
#include <libxml/tree.h>
#include <libxml/xmlsave.h>

#include "getprogname.h"

#include "guestfs.h"
#include "structs-cleanups.h"
#include "options.h"
#include "display-options.h"
#include "libxml2-writer-macros.h"

/* Currently open libguestfs handle. */
guestfs_h *g;

int read_only = 1;
int verbose = 0;
int keys_from_stdin = 0;
int echo_keys = 0;
const char *libvirt_uri = NULL;
int inspector = 1;
int in_guestfish = 0;
int in_virt_rescue = 0;
static const char *xpath = NULL;
static int inspect_apps = 1;
static int inspect_icon = 1;

static void output (char **roots);
static void output_roots (xmlTextWriterPtr xo, char **roots);
static void output_root (xmlTextWriterPtr xo, char *root);
static void output_mountpoints (xmlTextWriterPtr xo, char *root);
static void output_filesystems (xmlTextWriterPtr xo, char *root);
static void output_drive_mappings (xmlTextWriterPtr xo, char *root);
static void output_applications (xmlTextWriterPtr xo, char *root);
static void do_xpath (const char *query);

/* This macro is used by the macros in "libxml2-writer-macros.h"
 * when an error occurs.
 */
#define xml_error(fn)                                           \
  error (EXIT_FAILURE, errno,                                   \
         "%s:%d: error constructing XML near call to \"%s\"",   \
         __FILE__, __LINE__, (fn));

static void __attribute__((noreturn))
usage (int status)
{
  if (status != EXIT_SUCCESS)
    fprintf (stderr, _("Try ‘%s --help’ for more information.\n"),
             getprogname ());
  else {
    printf (_("%s: display information about a virtual machine\n"
              "Copyright (C) 2010 Red Hat Inc.\n"
              "Usage:\n"
              "  %s [--options] -d domname\n"
              "  %s [--options] -a disk.img [-a disk.img ...]\n"
              "Options:\n"
              "  -a|--add image       Add image\n"
              "  --blocksize[=512|4096]\n"
              "                       Set sector size of the disk for -a option\n"
              "  -c|--connect uri     Specify libvirt URI for -d option\n"
              "  -d|--domain guest    Add disks from libvirt guest\n"
              "  --echo-keys          Don't turn off echo for passphrases\n"
              "  --format[=raw|..]    Force disk format for -a option\n"
              "  --help               Display brief help\n"
              "  --key selector       Specify a LUKS key\n"
              "  --keys-from-stdin    Read passphrases from stdin\n"
              "  --no-applications    Do not output the installed applications\n"
              "  --no-icon            Do not output the guest icon\n"
              "  -v|--verbose         Verbose messages\n"
              "  -V|--version         Display version and exit\n"
              "  -x                   Trace libguestfs API calls\n"
              "  --xpath query        Perform an XPath query\n"
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

  static const char options[] = "a:c:d:vVx";
  static const struct option long_options[] = {
    { "add", 1, 0, 'a' },
    { "blocksize", 2, 0, 0 },
    { "connect", 1, 0, 'c' },
    { "domain", 1, 0, 'd' },
    { "echo-keys", 0, 0, 0 },
    { "format", 2, 0, 0 },
    { "help", 0, 0, HELP_OPTION },
    { "key", 1, 0, 0 },
    { "keys-from-stdin", 0, 0, 0 },
    { "long-options", 0, 0, 0 },
    { "no-applications", 0, 0, 0 },
    { "no-icon", 0, 0, 0 },
    { "short-options", 0, 0, 0 },
    { "verbose", 0, 0, 'v' },
    { "version", 0, 0, 'V' },
    { "xpath", 1, 0, 0 },
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
  struct key_store *ks = NULL;

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
      } else if (STREQ (long_options[option_index].name, "xpath")) {
        xpath = optarg;
      } else if (STREQ (long_options[option_index].name, "no-applications")) {
        inspect_apps = 0;
      } else if (STREQ (long_options[option_index].name, "no-icon")) {
        inspect_icon = 0;
      } else if (STREQ (long_options[option_index].name, "key")) {
        OPTION_key;
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
   * virt-inspector which is how we detect this.
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
  assert (inspector == 1);

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

  /* XPath is modal: no drives should be specified.  There must be
   * one extra parameter on the command line.
   */
  if (xpath) {
    if (drvs != NULL)
      error (EXIT_FAILURE, 0,
             _("cannot use --xpath together with other options."));

    do_xpath (xpath);

    exit (EXIT_SUCCESS);
  }

  /* User must have specified some drives. */
  if (drvs == NULL) {
    fprintf (stderr, _("%s: error: you must specify at least one -a or -d option.\n"),
             getprogname ());
    usage (EXIT_FAILURE);
  }

  /* Add drives, inspect and mount.  Note that inspector is always true,
   * and there is no -m option.
   */
  add_drives (drvs);

  if (key_store_requires_network (ks) && guestfs_set_network (g, 1) == -1)
    exit (EXIT_FAILURE);

  if (guestfs_launch (g) == -1)
    exit (EXIT_FAILURE);

  /* Free up data structures, no longer needed after this point. */
  free_drives (drvs);

  /* NB. Can't call inspect_mount () here (ie. normal processing of
   * the -i option) because it can only handle a single root.  So we
   * use low-level APIs.
   */
  inspect_do_decrypt (g, ks);

  free_key_store (ks);

  {
    CLEANUP_FREE_STRING_LIST char **roots = guestfs_inspect_os (g);
    if (roots == NULL)
      error (EXIT_FAILURE, 0,
             _("no operating system could be detected inside this disk image.\n\nThis may be because the file is not a disk image, or is not a virtual machine\nimage, or because the OS type is not understood by libguestfs.\n\nNOTE for Red Hat Enterprise Linux 6 users: for Windows guest support you must\ninstall the separate libguestfs-winsupport package.\n\nIf you feel this is an error, please file a bug report including as much\ninformation about the disk image as possible.\n"));

    output (roots);
  }

  guestfs_close (g);

  exit (EXIT_SUCCESS);
}

static void
output (char **roots)
{
  xmlOutputBufferPtr ob = xmlOutputBufferCreateFd (1, NULL);
  if (ob == NULL)
    error (EXIT_FAILURE, 0,
           _("xmlOutputBufferCreateFd: failed to open stdout"));

  /* 'ob' is freed when 'xo' is freed.. */
  CLEANUP_XMLFREETEXTWRITER xmlTextWriterPtr xo = xmlNewTextWriter (ob);
  if (xo == NULL)
    error (EXIT_FAILURE, 0,
           _("xmlNewTextWriter: failed to create libxml2 writer"));

  /* Pretty-print the output. */
  if (xmlTextWriterSetIndent (xo, 1) == -1 ||
      xmlTextWriterSetIndentString (xo, BAD_CAST "  ") == -1)
    error (EXIT_FAILURE, errno, "could not set XML indent");

  if (xmlTextWriterStartDocument (xo, NULL, NULL, NULL) == -1)
    error (EXIT_FAILURE, errno, "xmlTextWriterStartDocument");

  output_roots (xo, roots);

  if (xmlTextWriterEndDocument (xo) == -1)
    error (EXIT_FAILURE, errno, "xmlTextWriterEndDocument");
}

static void
output_roots (xmlTextWriterPtr xo, char **roots)
{
  size_t i;

  start_element ("operatingsystems") {
    for (i = 0; roots[i] != NULL; ++i)
      output_root (xo, roots[i]);
  } end_element ();
}

static void
output_root (xmlTextWriterPtr xo, char *root)
{
  char *str;
  int i;
  char *canonical_root;
  size_t size;

  start_element ("operatingsystem") {
    canonical_root = guestfs_canonical_device_name (g, root);
    if (canonical_root == NULL)
      exit (EXIT_FAILURE);
    single_element ("root", canonical_root);
    free (canonical_root);

    str = guestfs_inspect_get_type (g, root);
    if (!str) exit (EXIT_FAILURE);
    if (STRNEQ (str, "unknown"))
      single_element ("name", str);
    free (str);

    str = guestfs_inspect_get_arch (g, root);
    if (!str) exit (EXIT_FAILURE);
    if (STRNEQ (str, "unknown"))
      single_element ("arch", str);
    free (str);

    str = guestfs_inspect_get_distro (g, root);
    if (!str) exit (EXIT_FAILURE);
    if (STRNEQ (str, "unknown"))
      single_element ("distro", str);
    free (str);

    str = guestfs_inspect_get_product_name (g, root);
    if (!str) exit (EXIT_FAILURE);
    if (STRNEQ (str, "unknown"))
      single_element ("product_name", str);
    free (str);

    str = guestfs_inspect_get_product_variant (g, root);
    if (!str) exit (EXIT_FAILURE);
    if (STRNEQ (str, "unknown"))
      single_element ("product_variant", str);
    free (str);

    i = guestfs_inspect_get_major_version (g, root);
    single_element_format ("major_version", "%d", i);
    i = guestfs_inspect_get_minor_version (g, root);
    single_element_format ("minor_version", "%d", i);

    str = guestfs_inspect_get_package_format (g, root);
    if (!str) exit (EXIT_FAILURE);
    if (STRNEQ (str, "unknown"))
      single_element ("package_format", str);
    free (str);

    str = guestfs_inspect_get_package_management (g, root);
    if (!str) exit (EXIT_FAILURE);
    if (STRNEQ (str, "unknown"))
      single_element ("package_management", str);
    free (str);

    /* inspect-get-windows-systemroot will fail with non-windows guests,
     * or if the systemroot could not be determined for a windows guest.
     * Disable error output around this call.
     */
    guestfs_push_error_handler (g, NULL, NULL);
    str = guestfs_inspect_get_windows_systemroot (g, root);
    if (str)
      single_element ("windows_systemroot", str);
    free (str);
    str = guestfs_inspect_get_windows_current_control_set (g, root);
    if (str)
      single_element ("windows_current_control_set", str);
    free (str);
    guestfs_pop_error_handler (g);

    str = guestfs_inspect_get_hostname (g, root);
    if (!str) exit (EXIT_FAILURE);
    if (STRNEQ (str, "unknown"))
      single_element ("hostname", str);
    free (str);

    str = guestfs_inspect_get_osinfo (g, root);
    if (!str) exit (EXIT_FAILURE);
    if (STRNEQ (str, "unknown"))
      single_element ("osinfo", str);
    free (str);

    output_mountpoints (xo, root);

    output_filesystems (xo, root);

    output_drive_mappings (xo, root);

    /* We need to mount everything up in order to read out the list of
     * applications and the icon, ie. everything below this point.
     */
    if (inspect_apps || inspect_icon) {
      inspect_mount_root (g, root);

      if (inspect_apps)
        output_applications (xo, root);

      if (inspect_icon) {
        /* Don't return favicon.  RHEL 7 and Fedora have crappy 16x16
         * favicons in the base distro.
         */
        str = guestfs_inspect_get_icon (g, root, &size,
                                        GUESTFS_INSPECT_GET_ICON_FAVICON, 0,
                                        -1);
        if (!str) exit (EXIT_FAILURE);
        if (size > 0) {
          start_element ("icon") {
            base64 (str, size);
          } end_element ();
        }
        /* Note we must free (str) even if size == 0, because that indicates
         * there was no icon.
         */
        free (str);
      }

      /* Unmount (see inspect_mount_root above). */
      if (guestfs_umount_all (g) == -1)
        exit (EXIT_FAILURE);
    }
  } end_element (); /* operatingsystem */
}

static int
compare_keys (const void *p1, const void *p2)
{
  const char *key1 = * (char * const *) p1;
  const char *key2 = * (char * const *) p2;

  return strcmp (key1, key2);
}

static int
compare_keys_nocase (const void *p1, const void *p2)
{
  const char *key1 = * (char * const *) p1;
  const char *key2 = * (char * const *) p2;

  return strcasecmp (key1, key2);
}

static int
compare_keys_len (const void *p1, const void *p2)
{
  const char *key1 = * (char * const *) p1;
  const char *key2 = * (char * const *) p2;
  int c;

  c = strlen (key1) - strlen (key2);
  if (c != 0)
    return c;

  return compare_keys (p1, p2);
}

static void
output_mountpoints (xmlTextWriterPtr xo, char *root)
{
  size_t i;

  CLEANUP_FREE_STRING_LIST char **mountpoints =
    guestfs_inspect_get_mountpoints (g, root);
  if (mountpoints == NULL)
    exit (EXIT_FAILURE);

  /* Sort by key length, shortest key first, and then name, so the
   * output is stable.
   */
  qsort (mountpoints, guestfs_int_count_strings (mountpoints) / 2,
         2 * sizeof (char *),
         compare_keys_len);

  start_element ("mountpoints") {
    for (i = 0; mountpoints[i] != NULL; i += 2) {
      CLEANUP_FREE char *p =
        guestfs_canonical_device_name (g, mountpoints[i+1]);
      if (!p)
        exit (EXIT_FAILURE);

      start_element ("mountpoint") {
        attribute ("dev", p);
        string (mountpoints[i]);
      } end_element ();
    }
  } end_element ();
}

static void
output_filesystems (xmlTextWriterPtr xo, char *root)
{
  char *str;
  size_t i;

  CLEANUP_FREE_STRING_LIST char **filesystems =
    guestfs_inspect_get_filesystems (g, root);
  if (filesystems == NULL)
    exit (EXIT_FAILURE);

  /* Sort by name so the output is stable. */
  qsort (filesystems, guestfs_int_count_strings (filesystems), sizeof (char *),
         compare_keys);

  start_element ("filesystems") {
    for (i = 0; filesystems[i] != NULL; ++i) {
      str = guestfs_canonical_device_name (g, filesystems[i]);
      if (!str)
        exit (EXIT_FAILURE);

      start_element ("filesystem") {
        attribute ("dev", str);
        free (str);

        guestfs_push_error_handler (g, NULL, NULL);

        str = guestfs_vfs_type (g, filesystems[i]);
        if (str && str[0])
          single_element ("type", str);
        free (str);

        str = guestfs_vfs_label (g, filesystems[i]);
        if (str && str[0])
          single_element ("label", str);
        free (str);

        str = guestfs_vfs_uuid (g, filesystems[i]);
        if (str && str[0])
          single_element ("uuid", str);
        free (str);

        guestfs_pop_error_handler (g);
      } end_element ();
    }
  } end_element ();
}

static void
output_drive_mappings (xmlTextWriterPtr xo, char *root)
{
  CLEANUP_FREE_STRING_LIST char **drive_mappings = NULL;
  char *str;
  size_t i;

  guestfs_push_error_handler (g, NULL, NULL);
  drive_mappings = guestfs_inspect_get_drive_mappings (g, root);
  guestfs_pop_error_handler (g);
  if (drive_mappings == NULL)
    return;

  if (drive_mappings[0] == NULL)
    return;

  /* Sort by key. */
  qsort (drive_mappings,
         guestfs_int_count_strings (drive_mappings) / 2, 2 * sizeof (char *),
         compare_keys_nocase);

  start_element ("drive_mappings") {
    for (i = 0; drive_mappings[i] != NULL; i += 2) {
      str = guestfs_canonical_device_name (g, drive_mappings[i+1]);
      if (!str)
        exit (EXIT_FAILURE);

      start_element ("drive_mapping") {
        attribute ("name", drive_mappings[i]);
        string (str);
      } end_element ();

      free (str);
    }
  } end_element ();
}

static void
output_applications (xmlTextWriterPtr xo, char *root)
{
  size_t i;

  /* This returns an empty list if we simply couldn't determine the
   * applications, so if it returns NULL then it's a real error.
   */
  CLEANUP_FREE_APPLICATION2_LIST struct guestfs_application2_list *apps =
    guestfs_inspect_list_applications2 (g, root);
  if (apps == NULL)
    exit (EXIT_FAILURE);

  start_element ("applications") {
    for (i = 0; i < apps->len; ++i) {
      start_element ("application") {
        assert (apps->val[i].app2_name && apps->val[i].app2_name[0]);
        single_element ("name", apps->val[i].app2_name);

        if (apps->val[i].app2_display_name &&
            apps->val[i].app2_display_name[0])
          single_element ("display_name", apps->val[i].app2_display_name);

        if (apps->val[i].app2_epoch != 0)
          single_element_format ("epoch", "%d", apps->val[i].app2_epoch);

        if (apps->val[i].app2_version && apps->val[i].app2_version[0])
          single_element ("version", apps->val[i].app2_version);
        if (apps->val[i].app2_release && apps->val[i].app2_release[0])
          single_element ("release", apps->val[i].app2_release);
        if (apps->val[i].app2_arch && apps->val[i].app2_arch[0])
          single_element ("arch", apps->val[i].app2_arch);
        if (apps->val[i].app2_install_path &&
            apps->val[i].app2_install_path[0])
          single_element ("install_path", apps->val[i].app2_install_path);
        if (apps->val[i].app2_publisher && apps->val[i].app2_publisher[0])
          single_element ("publisher", apps->val[i].app2_publisher);
        if (apps->val[i].app2_url && apps->val[i].app2_url[0])
          single_element ("url", apps->val[i].app2_url);
        if (apps->val[i].app2_source_package &&
            apps->val[i].app2_source_package[0])
          single_element ("source_package", apps->val[i].app2_source_package);
        if (apps->val[i].app2_summary && apps->val[i].app2_summary[0])
          single_element ("summary", apps->val[i].app2_summary);
        if (apps->val[i].app2_description && apps->val[i].app2_description[0])
          single_element ("description", apps->val[i].app2_description);
      } end_element ();
    }
  } end_element ();
}

/* Run an XPath query on XML on stdin, print results to stdout. */
static void
do_xpath (const char *query)
{
  CLEANUP_XMLFREEDOC xmlDocPtr doc = NULL;
  CLEANUP_XMLXPATHFREECONTEXT xmlXPathContextPtr xpathCtx = NULL;
  CLEANUP_XMLXPATHFREEOBJECT xmlXPathObjectPtr xpathObj = NULL;
  xmlNodeSetPtr nodes;
  char *r;
  size_t i;
  xmlSaveCtxtPtr saveCtx;
  xmlNodePtr wrnode;

  doc = xmlReadFd (STDIN_FILENO, NULL, "utf8", XML_PARSE_NOBLANKS);
  if (doc == NULL)
    error (EXIT_FAILURE, 0, _("unable to parse XML from stdin"));

  xpathCtx = xmlXPathNewContext (doc);
  if (xpathCtx == NULL)
    error (EXIT_FAILURE, 0, _("unable to create new XPath context"));

  xpathObj = xmlXPathEvalExpression (BAD_CAST query, xpathCtx);
  if (xpathObj == NULL)
    error (EXIT_FAILURE, 0, _("unable to evaluate XPath expression"));

  switch (xpathObj->type) {
  case XPATH_NODESET:
    nodes = xpathObj->nodesetval;
    if (nodes == NULL)
      break;

    saveCtx = xmlSaveToFd (STDOUT_FILENO, NULL,
                           XML_SAVE_NO_DECL | XML_SAVE_FORMAT);
    if (saveCtx == NULL)
      error (EXIT_FAILURE, 0, _("xmlSaveToFd failed"));

    for (i = 0; i < (size_t) nodes->nodeNr; ++i) {
      CLEANUP_XMLFREEDOC xmlDocPtr wrdoc = xmlNewDoc (BAD_CAST "1.0");
      if (wrdoc == NULL)
        error (EXIT_FAILURE, 0, _("xmlNewDoc failed"));
      wrnode = xmlDocCopyNode (nodes->nodeTab[i], wrdoc, 1);
      if (wrnode == NULL)
        error (EXIT_FAILURE, 0, _("xmlCopyNode failed"));

      xmlDocSetRootElement (wrdoc, wrnode);

      if (xmlSaveDoc (saveCtx, wrdoc) == -1)
        error (EXIT_FAILURE, 0, _("xmlSaveDoc failed"));
    }

    xmlSaveClose (saveCtx);

    break;

  case XPATH_STRING:
    r = (char *) xpathObj->stringval;
    printf ("%s", r);
    i = strlen (r);
    if (i > 0 && r[i-1] != '\n')
      printf ("\n");
    break;

  case XPATH_UNDEFINED: /* grrrrr ... switch-enum is a useless warning */
  case XPATH_BOOLEAN:
  case XPATH_NUMBER:
  case XPATH_POINT:
  case XPATH_RANGE:
  case XPATH_LOCATIONSET:
  case XPATH_USERS:
  case XPATH_XSLT_TREE:
  default:
    r = (char *) xmlXPathCastToString (xpathObj);
    printf ("%s\n", r);
    free (r);
  }
}
