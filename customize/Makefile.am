# virt-customize
# Copyright (C) 2014-2023 Red Hat Inc.
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

include $(top_srcdir)/subdir-rules.mk

EXTRA_DIST = \
	$(SOURCES_MLI) $(SOURCES_ML) $(SOURCES_C) \
	test-password.pl \
	test-settings.sh \
	test-virt-customize.sh \
	test-virt-customize-docs.sh \
	virt-customize.pod

SOURCES_MLI = \
	customize_main.mli

SOURCES_ML = \
	customize_main.ml

if HAVE_OCAML

# Build the virt-customize program.
bin_PROGRAMS = virt-customize

virt_customize_SOURCES = dummy.c

CUSTOMIZE_BOBJECTS = customize_main.cmo
CUSTOMIZE_XOBJECTS = $(CUSTOMIZE_BOBJECTS:.cmo=.cmx)

if !HAVE_OCAMLOPT
CUSTOMIZE_THEOBJECTS = $(CUSTOMIZE_BOBJECTS)
else
CUSTOMIZE_THEOBJECTS = $(CUSTOMIZE_XOBJECTS)
endif

OCAMLLINKFLAGS = \
	mlstdutils.$(MLARCHIVE) \
	mlguestfs.$(MLARCHIVE) \
	mlgettext.$(MLARCHIVE) \
	mlpcre.$(MLARCHIVE) \
	mlxml.$(MLARCHIVE) \
	mlcutils.$(MLARCHIVE) \
	mltools.$(MLARCHIVE) \
	mlcustomize.$(MLARCHIVE) \
	$(LINK_CUSTOM_OCAMLC_ONLY)

OCAMLPACKAGES = \
	-package str,unix,guestfs \
	-I $(top_builddir)/common/utils/.libs \
	-I $(top_builddir)/gnulib/lib/.libs \
	-I $(top_builddir)/ocaml \
	-I $(top_builddir)/common/mlstdutils \
	-I $(top_builddir)/common/mlutils \
	-I $(top_builddir)/common/mlgettext \
	-I $(top_builddir)/common/mlpcre \
	-I $(top_builddir)/common/mlxml \
	-I $(top_builddir)/common/mltools \
	-I $(top_builddir)/common/mlcustomize \
	-I $(builddir)
if HAVE_OCAML_PKG_GETTEXT
OCAMLPACKAGES += -package gettext-stub
endif

OCAMLCLIBS = \
	-pthread -lpthread \
	-lutils \
	$(LIBTINFO_LIBS) \
	$(LIBGUESTFS_LIBS) \
	$(LIBCRYPT_LIBS) \
	$(LIBVIRT_LIBS) \
	$(LIBXML2_LIBS) \
	$(LIBOSINFO_LIBS) \
	$(LIBINTL) \
	-lgnu

OCAMLFLAGS = $(OCAML_FLAGS) $(OCAML_WARN_ERROR) -ccopt '$(CFLAGS)'

virt_customize_DEPENDENCIES = \
	$(top_builddir)/ocaml-link.sh \
	$(CUSTOMIZE_THEOBJECTS) \
	$(CUSTOMIZE_CMA) \
	../common/mlutils/mlcutils.$(MLARCHIVE) \
	../common/mlgettext/mlgettext.$(MLARCHIVE) \
	../common/mlpcre/mlpcre.$(MLARCHIVE) \
	../common/mlxml/mlxml.$(MLARCHIVE) \
	../common/mltools/mltools.$(MLARCHIVE) \
	../common/mlcustomize/mlcustomize.$(MLARCHIVE)
virt_customize_LINK = \
	$(top_builddir)/ocaml-link.sh -cclib '$(OCAMLCLIBS)' -- \
	  $(OCAMLFIND) $(BEST) $(OCAMLFLAGS) $(OCAMLPACKAGES) $(OCAMLLINKFLAGS) \
	  $(CUSTOMIZE_THEOBJECTS) -o $@

# Manual pages and HTML files for the website.
man_MANS = virt-customize.1
noinst_DATA = $(top_builddir)/website/virt-customize.1.html

virt-customize.1 $(top_builddir)/website/virt-customize.1.html: stamp-virt-customize.pod

stamp-virt-customize.pod: virt-customize.pod $(top_srcdir)/common/mlcustomize/customize-synopsis.pod $(top_srcdir)/common/mlcustomize/customize-options.pod
	$(PODWRAPPER) \
	  --man virt-customize.1 \
	  --html $(top_builddir)/website/virt-customize.1.html \
	  --path $(top_srcdir)/common/options \
	  --insert $(top_srcdir)/common/mlcustomize/customize-synopsis.pod:__CUSTOMIZE_SYNOPSIS__ \
	  --insert $(top_srcdir)/common/mlcustomize/customize-options.pod:__CUSTOMIZE_OPTIONS__ \
	  --license GPLv2+ \
	  --warning general \
	  $<
	touch $@

# Tests.

TESTS_ENVIRONMENT = $(top_builddir)/run --test

TESTS = \
	test-virt-customize-docs.sh \
	test-virt-customize.sh \
	$(SLOW_TESTS)

check-valgrind:
	$(MAKE) VG="@VG@" check

# Slow tests of virt-customize functionality in real guests.

SLOW_TESTS = \
	$(password_test_scripts) \
	$(settings_test_scripts)

check-slow:
	$(MAKE) check TESTS="$(SLOW_TESTS)" SLOW=1

password_test_scripts := \
	test-password-centos-7.2.sh \
	test-password-debian-6.sh \
	test-password-debian-7.sh \
	test-password-debian-8.sh \
	test-password-fedora-27.sh \
	test-password-rhel-3.9.sh \
	test-password-rhel-4.9.sh \
	test-password-rhel-5.11.sh \
	test-password-rhel-6.9.sh \
	test-password-rhel-7.2.sh \
	test-password-ubuntu-10.04.sh \
	test-password-ubuntu-12.04.sh \
	test-password-ubuntu-14.04.sh \
	test-password-ubuntu-16.04.sh \
	test-password-ubuntu-18.04.sh

test-password-%.sh:
	rm -f $@ $@-t
	f=`echo "$@" | $(SED) 's/test-password-\(.*\).sh/\1/'`; \
	echo 'script=$@ exec $$srcdir/test-password.pl' "$$f" > $@-t
	chmod 0755 $@-t
	mv $@-t $@

settings_test_scripts := \
	test-settings-rhel-4.9.sh \
	test-settings-rhel-5.11.sh \
	test-settings-rhel-6.8.sh \
	test-settings-rhel-7.2.sh \
	test-settings-debian-6.sh \
	test-settings-debian-7.sh \
	test-settings-debian-8.sh \
	test-settings-fedora-27.sh \
	test-settings-ubuntu-10.04.sh \
	test-settings-ubuntu-12.04.sh \
	test-settings-ubuntu-14.04.sh \
	test-settings-ubuntu-16.04.sh \
	test-settings-ubuntu-18.04.sh
# Since firstboot is broken, we cannot test settings in RHEL 3:
#	test-settings-rhel-3.9.sh

test-settings-%.sh:
	rm -f $@ $@-t
	f=`echo "$@" | $(SED) 's/test-settings-\(.*\).sh/\1/'`; \
	echo 'script=$@ exec $$srcdir/test-settings.sh' "$$f" > $@-t
	chmod 0755 $@-t
	mv $@-t $@

DISTCLEANFILES += \
	$(password_test_scripts) \
	$(settings_test_scripts)

CLEANFILES += \
	password-*.img \
	password-*.log \
	settings-*.img

# OCaml dependencies.
.depend: $(srcdir)/*.mli $(srcdir)/*.ml
	$(top_builddir)/ocaml-dep.sh $^
-include .depend

endif

.PHONY: docs
