#!/bin/bash -
# libguestfs virt-inspector test script
# Copyright (C) 2012-2025 Red Hat Inc.
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

# Test that virt-inspector can work on encrypted images when the
# right password is supplied.
#
# Regression test for https://bugzilla.redhat.com/show_bug.cgi?id=1658126

source ../tests/functions.sh
set -e
set -x

skip_if_skipped

# This test requires libguestfs >= 1.47.3.  Just check the minor
# number because this is a development branch so we can expect
# everyone to be at the latest version.
if [ "$(guestfish version | grep minor | awk '{print $2}')" -lt 47 ]; then
    echo "$0: test skipped because this requires libguestfs >= 1.47.3"
    exit 77
fi

f=../test-data/phony-guests/fedora-luks-on-lvm.img

keys=(--key /dev/Volume-Group/Root:key:FEDORA-Root
      --key /dev/Volume-Group/Logical-Volume-1:key:FEDORA-LV1
      --key /dev/Volume-Group/Logical-Volume-2:key:FEDORA-LV2
      --key /dev/Volume-Group/Logical-Volume-3:key:FEDORA-LV3)

keys_mapper=(--key /dev/mapper/Volume--Group-Root:key:FEDORA-Root
             --key /dev/mapper/Volume--Group-Logical--Volume--1:key:FEDORA-LV1
             --key /dev/mapper/Volume--Group-Logical--Volume--2:key:FEDORA-LV2
             --key /dev/mapper/Volume--Group-Logical--Volume--3:key:FEDORA-LV3)

keys_all=(--key all:key:FEDORA-Root
	  --key all:key:FEDORA-LV1
	  --key all:key:FEDORA-LV2
	  --key all:key:FEDORA-LV3)

# Ignore zero-sized file.
if [ -s "$f" ]; then
    uuid_root=$(guestfish --ro -i -a "$f" "${keys[@]}" \
                    luks-uuid /dev/Volume-Group/Root)
    b=$(basename "$f")
    $VG virt-inspector "${keys[@]}" --format=raw -a "$f" > "actual-$b.xml"
    # Check the generated output validate the schema.
    $XMLLINT --noout --relaxng "$srcdir/virt-inspector.rng" "actual-$b.xml"
    # This 'diff' command will fail (because of -e option) if there
    # are any differences.
    sed -e "s/ROOTUUID/$uuid_root/" < "$srcdir/expected-$b.xml" \
    | diff -u - "actual-$b.xml"

    # Re-run virt-inspector with keys using the /dev/mapper/VG-LV format; verify
    # only that the XML output matches the output from the previous
    # virt-inspector invocation (which used the /dev/VG/LV format).
    $VG virt-inspector "${keys_mapper[@]}" --format=raw -a "$f" \
    | diff -u "actual-$b.xml" -

    # Re-run using all:SELECTOR syntax.
    $VG virt-inspector "${keys_all[@]}" --format=raw -a "$f" \
    | diff -u "actual-$b.xml" -
fi
