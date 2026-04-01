#!/bin/bash -
# libguestfs virt-customize --root option test script
# Copyright (C) 2026 Red Hat Inc.
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
skip_unless_phony_guest fedora.img

f="$top_builddir/test-data/phony-guests/fedora.img"
virt_customize="$top_builddir/customize/virt-customize"
fq=test-virt-customize-root.qcow
out=test-virt-customize-root.out
rm -f $fq $out

qemu-img create -f qcow2 -b $f -F raw $fq

# Test --root all (default behavior, should work on single-OS guest).
$VG $virt_customize --format qcow2 -a $fq \
    --root all \
    --write /etc/test-root-all:PASS

# Verify.
guestfish --ro -a $fq -i cat /etc/test-root-all >$out
grep -sq PASS $out

# Re-create overlay.
rm -f $fq
qemu-img create -f qcow2 -b $f -F raw $fq

# Test --root single (should succeed on single-OS guest).
$VG $virt_customize --format qcow2 -a $fq \
    --root single \
    --write /etc/test-root-single:PASS

# Verify.
guestfish --ro -a $fq -i cat /etc/test-root-single >$out
grep -sq PASS $out

# Re-create overlay.
rm -f $fq
qemu-img create -f qcow2 -b $f -F raw $fq

# Test --root first (should pick the first root).
$VG $virt_customize --format qcow2 -a $fq \
    --root first \
    --write /etc/test-root-first:PASS

# Verify.
guestfish --ro -a $fq -i cat /etc/test-root-first >$out
grep -sq PASS $out

# Re-create overlay.
rm -f $fq
qemu-img create -f qcow2 -b $f -F raw $fq

# Test --root /dev/VG/Root (should pick the specific root).
$VG $virt_customize --format qcow2 -a $fq \
    --root /dev/VG/Root \
    --write /etc/test-root-dev:PASS

# Verify.
guestfish --ro -a $fq -i cat /etc/test-root-dev >$out
grep -sq PASS $out

# Test --root with invalid device (should fail).
rm -f $fq
qemu-img create -f qcow2 -b $f -F raw $fq

if $VG $virt_customize --format qcow2 -a $fq \
    --root /dev/sda99 \
    --write /etc/test-fail:FAIL 2>$out; then
    echo "$0: expected --root /dev/sda99 to fail"
    exit 1
fi
grep -sq "root device /dev/sda99 not found" $out

# Test --root with invalid option (should fail).
if $VG $virt_customize --format qcow2 -a $fq \
    --root bogus \
    --write /etc/test-fail:FAIL 2>$out; then
    echo "$0: expected --root bogus to fail"
    exit 1
fi
grep -sq "unknown --root option: bogus" $out

rm -f $fq $out
