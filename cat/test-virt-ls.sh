#!/bin/bash -
# libguestfs
# Copyright (C) 2012 Red Hat Inc.
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

set -e

$TEST_FUNCTIONS
skip_if_skipped

# Read out the test directory using virt-ls.
if [ "$($VG virt-ls --format=raw -a ../test-data/phony-guests/fedora.img /bin)" != "ls
rpm
test1
test2
test3
test4
test5
test6
test7" ]; then
    echo "$0: error: unexpected output from virt-ls"
    exit 1
fi

# Try the -lR option.
output="$($VG virt-ls -lR --format=raw -a ../test-data/phony-guests/fedora.img /boot | awk '{print $1 $2 $4}')"
expected="d0755/boot
d0755/boot/grub
-0644/boot/grub/grub.conf
-0644/boot/initramfs-5.19.0-0.rc1.14.fc37.x86_64.img
d0700/boot/lost+found
-0644/boot/vmlinuz-5.19.0-0.rc1.14.fc37.x86_64"
if [ "$output" != "$expected" ]; then
    echo "$0: error: unexpected output from virt-ls -lR"
    echo "output: ------------------------------------------"
    echo "$output"
    echo "expected: ----------------------------------------"
    echo "$expected"
    echo "--------------------------------------------------"
    exit 1
fi

# Try the -l and -R options.   XXX Should check the output.
$VG virt-ls -l ../test-data/phony-guests/fedora.img /
$VG virt-ls -R ../test-data/phony-guests/fedora.img /
