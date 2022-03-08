# guestfs-tools documentation
# Copyright (C) 2010-2022 Red Hat Inc.
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
	guestfs-tools-release-notes-1.48.pod

man_MANS = \
	guestfs-tools-release-notes-1.48.1
noinst_DATA = \
	$(top_builddir)/website/guestfs-tools-release-notes-1.48.1.html

guestfs-tools-release-notes-1.48.1 guestfs-tools-release-notes-1.48.txt $(top_builddir)/website/guestfs-tools-release-notes-1.48.1.html: stamp-guestfs-tools-release-notes-1.48.pod

stamp-guestfs-tools-release-notes-1.48.pod: guestfs-tools-release-notes-1.48.pod
	$(PODWRAPPER) \
	  --section 1 \
	  --man guestfs-tools-release-notes-1.48.1 \
	  --html $(top_builddir)/website/guestfs-tools-release-notes-1.48.1.html \
	  --license GPLv2+ \
	  $<
	touch $@
