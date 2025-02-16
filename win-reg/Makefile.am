# libguestfs virt-* tools
# Copyright (C) 2009-2025 Red Hat Inc.
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
