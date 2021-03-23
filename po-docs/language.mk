# libguestfs translations of man pages and POD files
# Copyright (C) 2010-2012 Red Hat Inc.
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

# Common logic for generating translated documentation.

include $(top_srcdir)/subdir-rules.mk

LINGUA = $(shell basename -- `pwd`)

# Before 1.23.23, the old Perl tools were called *.pl.
CLEANFILES += *.pl *.pod

MANPAGES = \
	virt-alignment-scan.1 \
	virt-builder.1 \
	virt-cat.1 \
	virt-copy-in.1 \
	virt-copy-out.1 \
	virt-customize.1 \
	virt-df.1 \
	virt-dib.1 \
	virt-diff.1 \
	virt-edit.1 \
	virt-filesystems.1 \
	virt-format.1 \
	virt-get-kernel.1 \
	virt-index-validate.1 \
	virt-inspector.1 \
	virt-log.1 \
	virt-ls.1 \
	virt-make-fs.1 \
	virt-resize.1 \
	virt-sparsify.1 \
	virt-sysprep.1 \
	virt-tar-in.1 \
	virt-tar-out.1 \
	virt-win-reg.1

podfiles := $(shell for f in `cat $(top_srcdir)/po-docs/podfiles`; do echo `basename $$f .pod`.pod; done)

# Ship the POD files and the translated manpages in the tarball.  This
# just simplifies building from the tarball, at a small cost in extra
# size.
EXTRA_DIST = \
	$(MANPAGES) \
	$(podfiles)

all-local: $(MANPAGES)

virt-builder.1: virt-builder.pod customize-synopsis.pod customize-options.pod
	$(PODWRAPPER) \
	  --no-strict-checks \
	  --man $@ \
	  --license GPLv2+ \
	  --insert $(srcdir)/customize-synopsis.pod:__CUSTOMIZE_SYNOPSIS__ \
	  --insert $(srcdir)/customize-options.pod:__CUSTOMIZE_OPTIONS__ \
	  --path $(top_srcdir)/common/options \
	  $<

virt-customize.1: virt-customize.pod customize-synopsis.pod customize-options.pod
	$(PODWRAPPER) \
	  --no-strict-checks \
	  --man $@ \
	  --license GPLv2+ \
	  --insert $(srcdir)/customize-synopsis.pod:__CUSTOMIZE_SYNOPSIS__ \
	  --insert $(srcdir)/customize-options.pod:__CUSTOMIZE_OPTIONS__ \
	  --path $(top_srcdir)/common/options \
	  $<

virt-sysprep.1: virt-sysprep.pod sysprep-extra-options.pod sysprep-operations.pod
	$(PODWRAPPER) \
	  --no-strict-checks \
	  --man $@ \
	  --license GPLv2+ \
          --insert $(srcdir)/sysprep-extra-options.pod:__EXTRA_OPTIONS__ \
          --insert $(srcdir)/sysprep-operations.pod:__OPERATIONS__ \
	  --path $(top_srcdir)/common/options \
	  $<

%.1: %.pod
	$(PODWRAPPER) \
	  --no-strict-checks \
	  --man $@ \
	  --path $(top_srcdir)/common/options \
	  $<

# Note: po4a puts the following junk at the top of every POD file it
# generates:
#  - a warning
#  - a probably bogus =encoding line
# Remove both.
# XXX Fix po4a so it doesn't do this.
%.pod: $(srcdir)/../$(LINGUA).po
	$(guestfs_am_v_po4a_translate)$(PO4A_TRANSLATE) \
	  -f pod \
	  -M utf-8 -L utf-8 \
	  -k 0 \
	  -m $(top_srcdir)/$(shell grep '/$(notdir $@)$$' $(top_srcdir)/po-docs/podfiles) \
	  -p $< \
	  | $(SED) '0,/^=encoding/d' > $@

# XXX Can automake do this properly?
install-data-hook:
	$(MKDIR_P) $(DESTDIR)$(mandir)/$(LINGUA)/man1
	$(INSTALL) -m 0644 $(srcdir)/*.1 $(DESTDIR)$(mandir)/$(LINGUA)/man1
