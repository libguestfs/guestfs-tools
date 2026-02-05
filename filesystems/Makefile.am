# libguestfs virt-filesystems
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
	test-virt-filesystems.sh \
	virt-filesystems.pod \
	$(NULL)

bin_PROGRAMS = virt-filesystems

virt_filesystems_SOURCES = filesystems.c

virt_filesystems_CPPFLAGS = \
	-DGUESTFS_NO_DEPRECATED=1 \
	-DLOCALEBASEDIR=\""$(datadir)/locale"\" \
	-I$(top_srcdir)/common/utils -I$(top_builddir)/common/utils \
	-I$(top_srcdir)/common/structs -I$(top_builddir)/common/structs \
	-I$(top_srcdir)/lib -I$(top_builddir)/lib \
	-I$(top_srcdir)/include \
	-I$(top_srcdir)/common/options -I$(top_builddir)/common/options \
	-I$(top_srcdir)/common/windows -I$(top_builddir)/common/windows \
	-I$(srcdir)/../gnulib/lib -I../gnulib/lib

virt_filesystems_CFLAGS = \
	$(WARN_CFLAGS) $(WERROR_CFLAGS) \
	$(LIBXML2_CFLAGS) \
	$(LIBGUESTFS_CFLAGS)

virt_filesystems_LDADD = \
	$(top_builddir)/common/options/liboptions.la \
	$(top_builddir)/common/windows/libwindows.la \
	$(top_builddir)/common/structs/libstructs.la \
	$(top_builddir)/common/utils/libutils.la \
	$(LIBGUESTFS_LIBS) \
	$(LIBXML2_LIBS) \
	$(LIBVIRT_LIBS) \
	$(LTLIBINTL) \
	../gnulib/lib/libgnu.la

# Manual pages and HTML files for the website.
man_MANS = virt-filesystems.1

noinst_DATA = $(top_builddir)/website/virt-filesystems.1.html

virt-filesystems.1 $(top_builddir)/website/virt-filesystems.1.html: stamp-virt-filesystems.pod

stamp-virt-filesystems.pod: virt-filesystems.pod
	$(PODWRAPPER) \
	  --man virt-filesystems.1 \
	  --html $(top_builddir)/website/virt-filesystems.1.html \
	  --path $(top_srcdir)/common/options \
	  --license GPLv2+ \
	  --warning safe \
	  $<
	touch $@
# Tests.

TESTS_ENVIRONMENT = $(top_builddir)/run --test

TESTS = \
	test-docs.sh \
	test-virt-filesystems.sh \
	$(NULL)

check-valgrind:
	$(MAKE) VG="@VG@" check

check-valgrind-local-guests:
	for g in $(GUESTS); do \
	  $(top_builddir)/run --test @VG@ virt-filesystems -c "$(libvirt_ro_uri)" -d "$$g" --all --long -h --uuid || exit $$?; \
	done
