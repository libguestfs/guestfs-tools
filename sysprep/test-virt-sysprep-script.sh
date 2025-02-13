#!/bin/bash -
# libguestfs virt-sysprep test --script option
# Copyright (C) 2011-2023 Red Hat Inc.
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

source ../tests/functions.sh
set -e
set -x

skip_if_skipped
skip_unless_fuse
skip_unless_phony_guest fedora.img

f=$top_builddir/test-data/phony-guests/fedora.img

# Export it down to the test scripts.
export abs_builddir

# Check that multiple scripts can run.
rm -f stamp-script1.sh stamp-script2.sh stamp-script4.sh
if ! virt-sysprep -q -n --format raw -a $f --enable script \
        --script $abs_srcdir/script1.sh --script $abs_srcdir/script2.sh; then
    echo "$0: virt-sysprep wasn't expected to exit with error."
    exit 1
fi
if [ ! -f stamp-script1.sh -o ! -f stamp-script2.sh ]; then
    echo "$0: one of the two test scripts did not run."
    exit 1
fi

# Check that if a script fails, virt-sysprep exits with an error.
if virt-sysprep -q -n --format raw -a $f --enable script \
        --script $abs_srcdir/script3.sh; then
    echo "$0: virt-sysprep didn't exit with an error."
    exit 1
fi

# Check that virt-sysprep uses a new temporary directory every time.
if ! virt-sysprep -q -n --format raw -a $f --enable script \
        --script $abs_srcdir/script4.sh; then
    echo "$0: virt-sysprep (script4.sh, try #1) wasn't expected to exit with error."
    exit 1
fi
if ! virt-sysprep -q -n --format raw -a $f --enable script \
        --script $abs_srcdir/script4.sh; then
    echo "$0: virt-sysprep (script4.sh, try #2) wasn't expected to exit with error."
    exit 1
fi
if [ x"`wc -l stamp-script4.sh | awk '{print $1}'`" != x2 ]; then
    echo "$0: stamp-script4.sh does not contain two lines."
    exit 1
fi
if [ x"`head -n1 stamp-script4.sh`" = x"`tail -n1 stamp-script4.sh`" ]; then
    echo "$0: stamp-script4.sh does not contain different paths."
    exit 1
fi
