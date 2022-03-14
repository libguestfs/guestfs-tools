# libguestfs
# Copyright (C) 2009-2021 Red Hat Inc.
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

AC_INIT([guestfs-tools], [1.48.0])

dnl The common/ subdirectory assumes this.  In libguestfs it contains
dnl the --with-extra parameter.  Here we just define it to the version.
PACKAGE_VERSION_FULL="$PACKAGE_VERSION"
AC_DEFINE_UNQUOTED([PACKAGE_VERSION_FULL],
                   ["$PACKAGE_VERSION_FULL"],[Full version string.])
AC_SUBST([PACKAGE_VERSION_FULL])

# Headings within the configure script output.
m4_define([HEADING],
          [AS_ECHO
           AS_ECHO(["--- $1 ---"])])

AC_CONFIG_AUX_DIR([build-aux])
AC_REQUIRE_AUX_FILE([guestfs-test-driver])

AC_USE_SYSTEM_EXTENSIONS

dnl Initialize automake.
AM_INIT_AUTOMAKE(foreign subdir-objects tar-pax) dnl NB: Do not [quote] this parameter.

m4_ifndef([AM_SILENT_RULES], [m4_define([AM_SILENT_RULES],[])])
AM_SILENT_RULES([yes]) # make --enable-silent-rules the default.

AC_CONFIG_MACRO_DIR([m4])

dnl Initialize libtool.
LT_INIT

dnl Check for external programs required to either build or run
dnl the tools.
HEADING([Checking for external programs])
m4_include([m4/guestfs-progs.m4])

dnl The C compiler environment.
HEADING([Checking for the C compiler environment])
m4_include([m4/guestfs-c.m4])

dnl Any C libraries required by the libguestfs C library (not the daemon).
HEADING([Checking for libraries used by libguestfs])
m4_include([m4/guestfs-libraries.m4])

dnl OCaml is required to compile several tools.
HEADING([Checking for OCaml compiler and libguestfs bindings])
m4_include([m4/guestfs-ocaml-gettext.m4])
m4_include([m4/guestfs-ocaml.m4])

dnl Perl is required for virt-win-reg, documentation and more.
HEADING([Checking for Perl])
m4_include([m4/guestfs-perl.m4])

dnl Miscellaneous libraries used by other programs.
HEADING([Checking for other libraries])
m4_include([m4/guestfs-misc-libraries.m4])

dnl Bash completion.
HEADING([Checking for bash completion])
m4_include([m4/guestfs-bash-completion.m4])

dnl Work around autoconf's lack of expanded variables.
eval my_sysconfdir="\"[$]sysconfdir\""
eval my_sysconfdir="\"$my_sysconfdir\""
SYSCONFDIR="${my_sysconfdir}"
AC_SUBST(SYSCONFDIR)

dnl This are required to get common/*/Makefile.am files to work.  We
dnl should further decouple these in future XXX
AM_CONDITIONAL([HAVE_PYTHON],[false])  dnl Disables a test
AM_CONDITIONAL([HAVE_BYTES_COMPAT_ML],[false])

dnl Produce output files.
HEADING([Generating output files])

AC_CONFIG_HEADERS([config.h])

AC_CONFIG_FILES([ocaml-dep.sh],
                [chmod +x,-w ocaml-dep.sh])
AC_CONFIG_FILES([ocaml-link.sh],
                [chmod +x,-w ocaml-link.sh])
AC_CONFIG_FILES([podwrapper.pl],
                [chmod +x,-w podwrapper.pl])
AC_CONFIG_FILES([run],
                [chmod +x,-w run])
AC_CONFIG_FILES([win-reg/virt-win-reg],
                [chmod +x,-w win-reg/virt-win-reg])

AC_CONFIG_FILES([Makefile
                 align/Makefile
                 bash/Makefile
                 builder/Makefile
                 builder/libguestfs.conf
                 builder/opensuse.conf
                 builder/templates/Makefile
                 builder/test-config/virt-builder/repos.d/test-index.conf
                 builder/test-simplestreams/virt-builder/repos.d/cirros.conf
                 builder/test-website/virt-builder/repos.d/libguestfs.conf
                 cat/Makefile
                 common/edit/Makefile
                 common/mlcustomize/Makefile
                 common/mlgettext/Makefile
                 common/mlpcre/Makefile
                 common/mlprogress/Makefile
                 common/mlstdutils/Makefile
                 common/mlstdutils/guestfs_config.ml
                 common/mltools/Makefile
                 common/mlutils/Makefile
                 common/mlvisit/Makefile
                 common/mlxml/Makefile
                 common/options/Makefile
                 common/parallel/Makefile
                 common/progress/Makefile
                 common/structs/Makefile
                 common/utils/Makefile
                 common/visit/Makefile
                 common/windows/Makefile
                 config.sh
                 customize/Makefile
                 docs/Makefile
                 df/Makefile
                 dib/Makefile
                 diff/Makefile
                 edit/Makefile
                 format/Makefile
                 get-kernel/Makefile
                 gnulib/lib/Makefile
                 inspector/Makefile
                 make-fs/Makefile
                 po-docs/Makefile
                 po-docs/ja/Makefile
                 po-docs/uk/Makefile
                 po/Makefile
                 resize/Makefile
                 sparsify/Makefile
                 sysprep/Makefile
                 test-data/Makefile
                 test-data/binaries/Makefile
                 test-data/blank-disks/Makefile
                 test-data/files/Makefile
                 test-data/phony-guests/Makefile
                 test-data/phony-guests/guests.xml
                 win-reg/Makefile])

AC_OUTPUT

dnl Produce summary.
echo
echo
echo "------------------------------------------------------------"
echo "Thank you for downloading $PACKAGE_STRING"
echo
echo "This is how we have configured the optional components for you today:"
echo
echo       "C-based virt tools .................. yes"
AS_ECHO_N(["GNU gettext for i18n ................ "])
if test "x$HAVE_GNU_GETTEXT_TRUE" = "x"; then echo "yes"; else echo "no"; fi
AS_ECHO_N(["OCaml-based virt tools .............. "])
if test "x$HAVE_OCAML_TRUE" = "x"; then echo "yes"; else echo "no"; fi
AS_ECHO_N(["Perl-based virt tools ............... "])
if test "x$HAVE_TOOLS_TRUE" = "x"; then echo "yes"; else echo "no"; fi
echo
echo "If any optional component is configured 'no' when you expected 'yes'"
echo "then you should check the preceding messages."
echo
echo "Please report bugs back to the mailing list:"
echo "http://www.redhat.com/mailman/listinfo/libguestfs"
echo
echo "Next you should type 'make' to build the package,"
echo "then 'make check' to run the tests."
echo "------------------------------------------------------------"
