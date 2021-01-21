# libguestfs virt-* tools
# Copyright (C) 2009-2020 Red Hat Inc.
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

EXTRA_DIST = virt-win-reg

bin_SCRIPTS = virt-win-reg

# Manual pages and HTML files for the website.

man_MANS = \
	virt-win-reg.1

virt-win-reg.1 $(top_builddir)/website/virt-win-reg.1.html: stamp-virt-win-reg.pod

stamp-virt-win-reg.pod: virt-win-reg
	$(PODWRAPPER) \
	  --man virt-win-reg.1 \
	  --html $(top_builddir)/website/virt-win-reg.1.html \
	  --license GPLv2+ \
	  --warning custom \
	  $<
	touch $@

all-local:
	for f in virt-win-reg; do echo win-reg/$$f; done \
	    > $(top_srcdir)/po/POTFILES-pl
