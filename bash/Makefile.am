# libguestfs
# Copyright (C) 2013-2020 Red Hat Inc.
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

scripts = \
	virt-alignment-scan \
	virt-win-reg

# Some of the scripts are simply symbolic links.
symlinks = \
	virt-builder \
	virt-cat \
	virt-customize \
	virt-diff \
	virt-df \
	virt-dib \
	virt-edit \
	virt-filesystems \
	virt-format \
	virt-get-kernel \
	virt-inspector \
	virt-log \
	virt-ls \
	virt-resize \
	virt-sparsify \
	virt-sysprep \
	virt-tail

# Note: Don't distribute the symbolic links, only the real files.
EXTRA_DIST = \
	README \
	$(scripts) \
	$(TESTS)

CLEANFILES += \
	$(symlinks)

# Any tool that has --short-options and --long-options and a few
# common options like -d is handled by this common script.  However
# this script cannot deal with commands that use --ro/--rw
# (eg. virt-rescue).  Those tools have to be handled individually.
virt-builder virt-cat virt-customize virt-df virt-dib virt-diff \
virt-edit virt-filesystems virt-format virt-get-kernel virt-inspector \
virt-log virt-ls \
virt-resize virt-sparsify virt-sysprep \
virt-tail:
	rm -f $@
	$(LN_S) virt-alignment-scan $@

if HAVE_BASH_COMPLETION

# Bash completion script.

bashcompletiondir = $(BASH_COMPLETIONS_DIR)
#bashcompletion_DATA = $(scripts)

all-local: $(scripts) $(symlinks)
	-test $(srcdir) != $(builddir) && cd $(srcdir) && cp $(scripts) $(abs_builddir)/

install-data-local:
	$(mkdir_p) $(DESTDIR)$(bashcompletiondir)
	cp -d $(scripts) $(symlinks) $(DESTDIR)$(bashcompletiondir)

clean-local:
	-test $(srcdir) != $(builddir) && rm -f $(scripts)

endif

# Tests.
TESTS_ENVIRONMENT = \
	scripts="$(scripts)" \
	symlinks="$(scripts)" \
	commands="$(scripts) $(symlinks)" \
	$(top_builddir)/run --test

TESTS = \
	test-complete-in-script.sh
