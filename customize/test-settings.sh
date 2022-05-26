#!/bin/bash -
# Test various virt-customize settings.
# Copyright (C) 2016 Red Hat Inc.
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

# This slow test checks that settings such as hostname, timezone work.
#
# NB. 'test-settings.sh' runs the tests, but the various tests are
# run via the 'test-settings-GUESTNAME.sh' wrappers.

set -e
set -x

$TEST_FUNCTIONS
slow_test
skip_if_skipped "$script"

guestname="$1"
if [ -z "$guestname" ]; then
    echo "$script: guestname parameter not set, don't run this test directly."
    exit 1
fi

# Undefine this which is set by ./run script, since we want to use the
# public virt-builder templates.
unset VIRT_BUILDER_DIRS

disk="settings-$guestname.img"
rm -f "$disk" "$disk.firstboot.sh" "$disk.firstboot.out"

# If the guest doesn't exist in virt-builder, skip.  This is because
# we test some RHEL guests which most users won't have access to.
skip_unless_virt_builder_guest "$guestname"

# We can only run the tests on x86_64.
skip_unless_arch x86_64

# Check qemu is installed.
qemu=qemu-system-x86_64
skip_unless $qemu -help

# Some guests need special virt-builder parameters.
# See virt-builder --notes "$guestname"
declare -a extra
case "$guestname" in
    debian-6|debian-7)
        extra[${#extra[*]}]='--edit'
        extra[${#extra[*]}]='/etc/inittab:
                                s,^#([1-9].*respawn.*/sbin/getty.*),$1,'
        ;;
    *)
        ;;
esac

# Create a firstboot script.  Broadly the same across all distros, but
# could be different in future if we support non-Linux (XXX).
fb="$disk.firstboot.sh"
case "$guestname" in
    centos*|debian*|fedora*|rhel*|ubuntu*)
        echo '#!/bin/sh'                                > "$fb"
        echo 'exec > /firstboot.out 2> /firstboot.err' >> "$fb"

        # Only some guests can read the short hostname properly.
        case "$guestname" in
            debian*|fedora*|ubuntu*)
                echo 'echo -n HOSTNAME='               >> "$fb"
                echo 'hostname -s'                     >> "$fb"
                ;;
        esac

        # Only some guests can read the FQDN properly.
        case "$guestname" in
            ubuntu-10.04) ;;
            fedora*|debian*|ubuntu*)
                echo 'echo -n FQDN='                   >> "$fb"
                echo 'hostname -f'                     >> "$fb"
                ;;
        esac

        # RHEL 4.9 did not have "%:z".
        case "$guestname" in
            rhel-4.9) ;;
            *)
                echo 'echo -n TIMEZONE='               >> "$fb"
                echo 'date +%:z'                       >> "$fb"
        esac

        echo 'sync'                                    >> "$fb"
        echo 'poweroff'                                >> "$fb"
        ;;
    *)
        echo "$script: don't know how to write a firstboot script for $guestname"
        exit 1
        ;;
esac

# Build a guest (using virt-builder) with some virt-customize setting
# parameters.
#
# Note we choose a timezone that doesn't have daylight savings, so
# that the output of the date command should always be the same.
virt-builder "$guestname" \
             --quiet \
             -o "$disk" \
             --hostname test-set.example.com \
             --timezone Japan \
             --firstboot "$fb" \
             "${extra[@]}"

# Boot the guest in qemu and wait for the firstboot scripts to run.
#
# Use IDE because some ancient guests don't support anything else.
$qemu \
    -no-user-config \
    -display none \
    -machine accel=kvm:tcg \
    -m 2048 \
    -boot c \
    -drive file="$disk",format=raw,if=ide \
    -serial stdio ||:

# Get the output of the firstboot script.
fbout="$disk.firstboot.out"
guestfish --ro -a "$disk" -i <<EOF
download /firstboot.out "$fbout"

# For information/debugging only.
echo === /firstboot.out ===
-cat /firstboot.out
echo === /firstboot.err ===
-cat /firstboot.err
echo === /etc/hosts ===
-cat /etc/hosts
echo === /etc/hostname ===
-cat /etc/hostname
echo === /etc/sysconfig/network ===
-cat /etc/sysconfig/network

EOF

# Check the output of the firstboot script.
if grep "^HOSTNAME=" "$fbout"; then
    grep "^HOSTNAME=test-set" "$fbout"
fi
if grep "^FQDN=" "$fbout"; then
    grep "^FQDN=test-set.example.com" "$fbout"
fi
if grep "^TIMEZONE=" "$fbout"; then
    grep "^TIMEZONE=+09:00" "$fbout"
fi

rm "$disk" "$disk.firstboot.sh" "$disk.firstboot.out"
