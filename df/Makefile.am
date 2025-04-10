# libguestfs virt-df
# Copyright (C) 2010-2025 Red Hat Inc.
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
	README \
	test-virt-df.sh \
	test-virt-df-docs.sh \
	test-virt-df-guests.sh \
	virt-df.pod

bin_PROGRAMS = virt-df

virt_df_SOURCES = \
	virt-df.h \
	df.c \
	main.c \
	output.c

virt_df_CPPFLAGS = \
	-DGUESTFS_NO_DEPRECATED=1 \
	-DLOCALEBASEDIR=\""$(datadir)/locale"\" \
	-I$(top_srcdir)/common/utils -I$(top_builddir)/common/utils \
	-I$(top_srcdir)/common/structs -I$(top_builddir)/common/structs \
	-I$(top_srcdir)/lib -I$(top_builddir)/lib \
	-I$(top_srcdir)/include \
	-I$(top_srcdir)/common/options -I$(top_builddir)/common/options \
	-I$(top_srcdir)/common/parallel -I$(top_builddir)/common/parallel \
	-I$(srcdir)/../gnulib/lib -I../gnulib/lib

virt_df_CFLAGS = \
	-pthread \
	$(WARN_CFLAGS) $(WERROR_CFLAGS) \
	$(LIBGUESTFS_CFLAGS) \
	$(LIBXML2_CFLAGS) \
	$(LIBVIRT_CFLAGS)

virt_df_LDADD = \
	$(top_builddir)/common/options/liboptions.la \
	$(top_builddir)/common/parallel/libparallel.la \
	$(top_builddir)/common/structs/libstructs.la \
	$(top_builddir)/common/utils/libutils.la \
	$(LIBGUESTFS_LIBS) \
	$(LIBXML2_LIBS) \
	$(LIBVIRT_LIBS) \
	$(LTLIBINTL) \
	../gnulib/lib/libgnu.la \
	-lm

# Manual pages and HTML files for the website.
man_MANS = virt-df.1
noinst_DATA = $(top_builddir)/website/virt-df.1.html

virt-df.1 $(top_builddir)/website/virt-df.1.html: stamp-virt-df.pod

stamp-virt-df.pod: virt-df.pod
	$(PODWRAPPER) \
	  --man virt-df.1 \
	  --html $(top_builddir)/website/virt-df.1.html \
	  --path $(top_srcdir)/common/options \
	  --license GPLv2+ \
	  --warning safe \
	  $<
	touch $@

# Tests.

TESTS_ENVIRONMENT = $(top_builddir)/run --test

TESTS = \
	test-virt-df-docs.sh \
	test-virt-df.sh

if HAVE_LIBVIRT
TESTS += \
	test-virt-df-guests.sh
endif

check-valgrind:
	$(MAKE) VG="@VG@" check

check-valgrind-local-guests:
	$(top_builddir)/run --test @VG@ virt-df -c "$(libvirt_ro_uri)"
