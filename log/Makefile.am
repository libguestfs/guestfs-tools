# libguestfs virt-log
# Copyright (C) 2010-2026 Red Hat Inc.
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
	test-docs.sh \
	test-virt-log.sh \
	virt-log.pod \
	$(NULL)

bin_PROGRAMS = virt-log

virt_log_SOURCES = log.c

virt_log_CPPFLAGS = \
	-DGUESTFS_NO_DEPRECATED=1 \
	-DLOCALEBASEDIR=\""$(datadir)/locale"\" \
	-I$(top_srcdir)/common/utils -I$(top_builddir)/common/utils \
	-I$(top_srcdir)/common/structs -I$(top_builddir)/common/structs \
	-I$(top_srcdir)/lib -I$(top_builddir)/lib \
	-I$(top_srcdir)/include \
	-I$(top_srcdir)/common/options -I$(top_builddir)/common/options \
	-I$(top_srcdir)/common/windows -I$(top_builddir)/common/windows \
	-I$(srcdir)/../gnulib/lib -I../gnulib/lib

virt_log_CFLAGS = \
	$(WARN_CFLAGS) $(WERROR_CFLAGS) \
	$(LIBXML2_CFLAGS) \
	$(LIBGUESTFS_CFLAGS)

virt_log_LDADD = \
	$(top_builddir)/common/options/liboptions.la \
	$(top_builddir)/common/structs/libstructs.la \
	$(top_builddir)/common/utils/libutils.la \
	$(LIBGUESTFS_LIBS) \
	$(LIBXML2_LIBS) \
	$(LIBVIRT_LIBS) \
	$(LTLIBINTL) \
	../gnulib/lib/libgnu.la

# Manual pages and HTML files for the website.
man_MANS = virt-log.1

noinst_DATA = $(top_builddir)/website/virt-log.1.html

virt-log.1 $(top_builddir)/website/virt-log.1.html: stamp-virt-log.pod

stamp-virt-log.pod: virt-log.pod
	$(PODWRAPPER) \
	  --man virt-log.1 \
	  --html $(top_builddir)/website/virt-log.1.html \
	  --path $(top_srcdir)/common/options \
	  --license GPLv2+ \
	  --warning safe \
	  $<
	touch $@

# Tests.

TESTS_ENVIRONMENT = $(top_builddir)/run --test

TESTS = \
	test-docs.sh \
	test-virt-log.sh \
	$(NULL)

check-valgrind:
	$(MAKE) VG="@VG@" check
