#!/bin/bash -
# libguestfs
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

set -e

$TEST_FUNCTIONS
skip_if_skipped

rm -f test.qcow2

# Make a copy of the Fedora image so we can write to it then
# discard it.
guestfish -- \
  disk-create test.qcow2 qcow2 -1 \
    backingfile:../test-data/phony-guests/fedora.img backingformat:raw

# Edit interactively.  We have to simulate this by setting $EDITOR.
# The command will be: echo newline >> /tmp/file
export EDITOR='echo newline >>'
virt-edit --format=qcow2 -a test.qcow2 /etc/test3
if [ "$(virt-cat -a test.qcow2 /etc/test3)" != "a
b
c
d
e
f
newline" ]; then
    echo "$0: error: mismatch in interactive editing of file /etc/test3"
    exit 1
fi
unset EDITOR

# Edit non-interactively, only if we have 'perl' binary.
if perl --version >/dev/null 2>&1; then
    virt-edit --format=qcow2 -a test.qcow2 /etc/test3 -e 's/^[a-f]/$lineno/'
    if [ "$(virt-cat -a test.qcow2 /etc/test3)" != "1
2
3
4
5
6
newline" ]; then
        echo "$0: error: mismatch in non-interactive editing of file /etc/test3"
        exit 1
    fi
fi

# Verify the mode of /etc/test3 is still 0600 and the UID:GID is 10:11.
# See test-data/phony-guests/make-fedora-img.pl and RHBZ#788641.
if [ "$(guestfish -i --format=qcow2 -a test.qcow2 --ro lstat /etc/test3 | grep -E '^(mode|uid|gid):' | sort)" != "gid: 11
mode: 33152
uid: 10" ]; then
    echo "$0: error: editing /etc/test3 did not preserve permissions or ownership"
    exit 1
fi

# Discard test image.
rm test.qcow2
