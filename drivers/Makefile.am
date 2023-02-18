# virt-drivers tool
# Copyright (C) 2009-2023 Red Hat Inc.
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
	expected-fedora.xml \
	expected-windows.xml \
	test-virt-drivers-docs.sh \
	test-virt-drivers-linux.sh \
	test-virt-drivers-windows.sh \
	virt-drivers.pod

SOURCES_MLI = \
	drivers.mli \
	hwdata_config.mli \
	hwdata.mli

SOURCES_ML = \
	hwdata_config.ml \
	hwdata.ml \
	drivers.ml

SOURCES_C = \
	dummy.c

man_MANS =
noinst_DATA =
bin_PROGRAMS =

if HAVE_OCAML

bin_PROGRAMS += virt-drivers

virt_drivers_SOURCES = $(SOURCES_C)
virt_drivers_CPPFLAGS = \
	-I. \
	-I$(top_builddir) \
	-I$(top_srcdir)/gnulib/lib -I$(top_builddir)/gnulib/lib \
	-I$(shell $(OCAMLC) -where) \
	-I$(top_srcdir)/gnulib/lib \
	-I$(top_srcdir)/common/utils \
	-I$(top_srcdir)/lib
virt_drivers_CFLAGS = \
	-pthread \
	$(WARN_CFLAGS) $(WERROR_CFLAGS) \
	$(LIBXML2_CFLAGS)

BOBJECTS = $(SOURCES_ML:.ml=.cmo)
XOBJECTS = $(BOBJECTS:.cmo=.cmx)

OCAMLPACKAGES = \
	-package str,unix,guestfs \
	-I $(top_builddir)/common/utils/.libs \
	-I $(top_builddir)/gnulib/lib/.libs \
	-I $(top_builddir)/ocaml \
	-I $(top_builddir)/common/mlstdutils \
	-I $(top_builddir)/common/mlutils \
	-I $(top_builddir)/common/mlgettext \
	-I $(top_builddir)/common/mlpcre \
	-I $(top_builddir)/common/mltools \
	-I $(top_builddir)/common/mldrivers
if HAVE_OCAML_PKG_GETTEXT
OCAMLPACKAGES += -package gettext-stub
endif

OCAMLCLIBS = \
	-pthread -lpthread \
	-lutils \
	$(LIBXML2_LIBS) \
	$(LIBGUESTFS_LIBS) \
	$(LIBINTL) \
	-lgnu

OCAMLFLAGS = $(OCAML_FLAGS) $(OCAML_WARN_ERROR) -ccopt '$(CFLAGS)'

if !HAVE_OCAMLOPT
OBJECTS = $(BOBJECTS)
else
OBJECTS = $(XOBJECTS)
endif

OCAMLLINKFLAGS = \
	mlstdutils.$(MLARCHIVE) \
	mlguestfs.$(MLARCHIVE) \
	mlgettext.$(MLARCHIVE) \
	mlpcre.$(MLARCHIVE) \
	mlcutils.$(MLARCHIVE) \
	mltools.$(MLARCHIVE) \
	mldrivers.$(MLARCHIVE) \
	$(LINK_CUSTOM_OCAMLC_ONLY)

virt_drivers_DEPENDENCIES = \
	$(OBJECTS) \
	../common/mlstdutils/mlstdutils.$(MLARCHIVE) \
	../common/mlutils/mlcutils.$(MLARCHIVE) \
	../common/mlgettext/mlgettext.$(MLARCHIVE) \
	../common/mlpcre/mlpcre.$(MLARCHIVE) \
	../common/mltools/mltools.$(MLARCHIVE) \
	../common/mldrivers/mldrivers.$(MLARCHIVE) \
	$(top_builddir)/ocaml-link.sh
virt_drivers_LINK = \
	$(top_builddir)/ocaml-link.sh -cclib '$(OCAMLCLIBS)' -- \
	  $(OCAMLFIND) $(BEST) $(OCAMLFLAGS) $(OCAMLPACKAGES) $(OCAMLLINKFLAGS) \
	  $(OBJECTS) -o $@

# Tests.

TESTS_ENVIRONMENT = $(top_builddir)/run --test

TESTS = \
	test-virt-drivers-docs.sh \
	test-virt-drivers-linux.sh \
	test-virt-drivers-windows.sh

check-valgrind:
	$(MAKE) VG="@VG@" check

# Manual pages and HTML files for the website.

man_MANS += virt-drivers.1
noinst_DATA += $(top_builddir)/website/virt-drivers.1.html

virt-drivers.1 $(top_builddir)/website/virt-drivers.1.html: stamp-virt-drivers.pod

stamp-virt-drivers.pod: virt-drivers.pod
	$(PODWRAPPER) \
	  --man virt-drivers.1 \
	  --html $(top_builddir)/website/virt-drivers.1.html \
	  --path $(top_srcdir)/common/options \
	  --license GPLv2+ \
	  --warning safe \
	  $<
	touch $@

# OCaml dependencies.
.depend: $(srcdir)/*.mli $(srcdir)/*.ml
	$(top_builddir)/ocaml-dep.sh $^
-include .depend

endif
