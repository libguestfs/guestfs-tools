# guestfs tools
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

include $(top_srcdir)/common-rules.mk

ACLOCAL_AMFLAGS = -I m4

# Common code.
SUBDIRS  = gnulib/lib
SUBDIRS += common/utils
SUBDIRS += common/structs
if HAVE_OCAML
SUBDIRS += common/mlstdutils
SUBDIRS += common/mlutils
SUBDIRS += common/mlpcre
endif
SUBDIRS += common/edit
SUBDIRS += common/options
SUBDIRS += common/parallel
SUBDIRS += common/progress
SUBDIRS += common/visit
SUBDIRS += common/windows
if HAVE_OCAML
SUBDIRS += common/mlgettext
SUBDIRS += common/mlprogress
SUBDIRS += common/mlvisit
SUBDIRS += common/mlxml
SUBDIRS += common/mltools
SUBDIRS += common/mldrivers
SUBDIRS += common/mlcustomize
endif

# Data used by the tests.
SUBDIRS += test-data

# virt-tools in C.
SUBDIRS += align cat diff df edit format inspector make-fs

if HAVE_OCAML
# OCaml tools.  Note 'common/ml*' and 'customize' contain shared code
# used by other OCaml tools, so these must come first.
SUBDIRS += customize
SUBDIRS += builder builder/templates
SUBDIRS += drivers
SUBDIRS += get-kernel
SUBDIRS += resize
SUBDIRS += sparsify
SUBDIRS += sysprep
endif

# bash-completion
SUBDIRS += bash

if HAVE_TOOLS
# Perl tools.
SUBDIRS += win-reg
endif

# Miscellaneous documentation.
SUBDIRS += docs

# After all source files were used we can generate the translation strings
SUBDIRS += po
if HAVE_PO4A
SUBDIRS += po-docs
endif

EXTRA_DIST = \
	HACKING \
	README \
	.gitignore \
	bugs-in-changelog.sh \
	check-mli.sh \
	common/.gitignore \
	common/README \
	lib/guestfs-internal-all.h \
	m4/.gitignore \
	podcheck.pl \
	test-functions.sh \
	tmp/.gitignore \
	valgrind-suppressions

# When doing 'make dist' update a few files automatically.
#
#  po/POTFILES    - files with ordinary extensions, but not OCaml files
#  po/POTFILES-pl - Perl files that don't end in *.pl, which need a
#                   special xgettext option [not generated here]
#  po/POTFILES-ml - OCaml files, which need a special tool to translate
#  po-docs/guestfs-tools-docs.pot
#                 - combined list of strings from documentation

dist-hook: po/POTFILES po/POTFILES-ml
	rm -f po-docs/guestfs-tools-docs.pot
	$(MAKE) -C po-docs guestfs-tools-docs.pot

# For more information about translations, see po/Makefile.am.
po/POTFILES: configure.ac
	rm -f $@ $@-t
	cd $(srcdir); \
	find $(DIST_SUBDIRS) -name '*.c' | \
	grep -v -E '^(examples|gnulib|perl/(blib|examples)|po-docs|tests|test-data|bundled)/' | \
	grep -v -E '/((guestfs|rc)_protocol\.c|dummy\.c)$$' | \
	grep -v -E '^python/utils\.c$$' | \
	grep -v -E '^perl/lib/Sys/Guestfs\.c$$' | \
	grep -v -E '^common/errnostring' | \
	grep -v -E '.*-(tests|gperf)\.c$$' | \
	LC_ALL=C sort -u > $@-t
	mv $@-t $@

po/POTFILES-ml: configure.ac
	rm -f $@ $@-t
	cd $(srcdir); \
	find builder common/ml* customize drivers get-kernel resize sparsify sysprep -name '*.ml' | \
	grep -v '^builder/templates/' | \
	grep -v '^common/mlv2v/' | \
	grep -v -E '.*_tests\.ml$$' | \
	LC_ALL=C sort > $@-t
	mv $@-t $@

# NB. podwrapper is an internal tool, so the man page mustn't be installed.
# It should be noinst_MANS but that doesn't work.
noinst_DATA = podwrapper.1
podwrapper.1: podwrapper.pl
	$(PODWRAPPER) \
	  --section 1 \
	  --man $@-t \
	  --license GPLv2+ \
	  --warning safe \
	  $<
	mv $@-t $@

# Make clean.
CLEANFILES += \
	pod2htm?.tmp

clean-local:
	-rm -rf tmp/libguestfs??????
	-rm -rf tmp/guestfs.*
	-rm -rf tmp/.guestfs-*
	-rm -rf tmp/null.*
	-find tmp -type s -delete
	-find . -name '*~' -delete

# Tests.
TESTS = check-mli.sh

build-test-guests:
	$(MAKE) -C test-data/phony-guests check

check-valgrind: build-test-guests
	@errors=0; \
	for f in `grep -l '^$@:' $(SUBDIRS:%=%/Makefile.am)`; do \
	  echo $(MAKE) -C `dirname $$f` $@; \
	  $(MAKE) -C `dirname $$f` $@ || (( errors++ )); \
	done; \
	exit $$(( $$errors ? 1 : 0 ))

check-slow: build-test-guests
	@errors=0; \
	for f in `grep -l '^$@:' $(SUBDIRS:%=%/Makefile.am)`; do \
	  echo $(MAKE) -C `dirname $$f` $@; \
	  $(MAKE) -C `dirname $$f` $@ || (( errors++ )); \
	done; \
	exit $$(( $$errors ? 1 : 0 ))

# Commit everything in current directory to HEAD, and set commit
# message to current version (only for maintainer).

maintainer-commit:
	git commit -a -m "Version $(VERSION)."

# Tag HEAD with current version (only for maintainer).

maintainer-tag:
	git tag -a "v$(VERSION)" -m "Version $(VERSION)" -f

# Maintainer only: check no files are missing from EXTRA_DIST rules,
# and that all generated files have been included in the tarball.
# (Note you must have done 'make dist')

maintainer-check-extra-dist:
	zcat $(PACKAGE_NAME)-$(VERSION).tar.gz | tar tf - | sort | \
	  sed 's,^$(PACKAGE_NAME)-$(VERSION)/,,' > tmp/tarfiles
	( git ls-files ; \
	  cd common; git ls-files | sed 's,^,common/,' ) | \
	  grep -v '^common$$' | \
	  grep -v '^common/errnostring/' | \
	  grep -v '^common/mlv2v/' | \
	  grep -v '^common/protocol/' | \
	  grep -v '^common/qemuopts/' | \
	  grep -v '^intltool-.*\.in' | \
	  grep -v '^\.gitmodules' | \
	  grep -v '^\.gnulib' | \
	  sort > tmp/gitfiles
	comm -13 tmp/tarfiles tmp/gitfiles > tmp/comm-out
	@echo Checking for differences between EXTRA_DIST and git ...
	cat tmp/comm-out
	[ ! -s tmp/comm-out ]
	rm tmp/tarfiles tmp/gitfiles tmp/comm-out
	@echo PASS: EXTRA_DIST tests
