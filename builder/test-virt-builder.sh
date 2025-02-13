#!/bin/bash -
# libguestfs virt-builder test script
# Copyright (C) 2013 Red Hat Inc.
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

export XDG_CONFIG_HOME=
export VIRT_BUILDER_DIRS="$abs_builddir/test-config"

if [ ! -f fedora.xz ]; then
    echo "$0: test skipped because there is no fedora.xz in the build directory"
    exit 77
fi

output=phony-fedora.img

rm -f $output

# Test as many options as we can!
#
# Note we cannot test --install, --run since the phony Fedora doesn't
# have a real OS inside just some configuration files.  Just about
# every other option is fair game.
#
# Don't use $VG here, because libtool (expanded from $VG) chokes
# on the multi-line parameters. (RHBZ#1420301)
virt-builder phony-fedora \
    -v --no-cache --no-check-signature $no_network \
    -o $output --size 2G --format qcow2 \
    --arch x86_64 \
    --hostname test.example.com \
    --timezone Europe/London \
    --root-password password:123456 \
    --mkdir /etc/foo/bar/baz \
    --write '/etc/foo/bar/baz/foo:Hello World' \
    --upload Makefile:/Makefile \
    --edit '/Makefile: s{^#.*}{}' \
    --upload Makefile:/etc/foo/bar/baz \
    --delete /Makefile \
    --link /etc/foo/bar/baz/foo:/foo \
    --link /etc/foo/bar/baz/foo:/foo1:/foo2:/foo3 \
    --append-line '/etc/append1:hello' \
    --append-line '/etc/append2:line1' \
    --append-line '/etc/append2:line2' \
    --write '/etc/append3:line1' \
    --append-line '/etc/append3:line2' \
    --write '/etc/append4:line1
' \
    --append-line '/etc/append4:line2' \
    --touch /etc/append5 \
    --append-line '/etc/append5:line1' \
    --write '/etc/append6:
' \
    --append-line '/etc/append6:line2' \
    --chown 1:1:/etc/append6 \
    --firstboot Makefile --firstboot-command 'echo "hello"' \
    --firstboot-install "minicom,inkscape"

# Check that some modifications were made.
$VG guestfish --ro -i -a $output > test-virt-builder.out <<EOF
# Uploaded files
is-file /etc/foo/bar/baz/Makefile
cat /etc/foo/bar/baz/foo
is-symlink /foo
is-symlink /foo1
is-symlink /foo2
is-symlink /foo3

echo -----
# Hostname
cat /etc/sysconfig/network | grep HOSTNAME=

echo -----
# Timezone
is-file /usr/share/zoneinfo/Europe/London
is-symlink /etc/localtime
readlink /etc/localtime

echo -----
# Password
is-file /etc/shadow
cat /etc/shadow | sed -r '/^root:/!d;s,^(root:\\\$6\\\$).*,\\1,g'

echo -----
# Line appending
# Note that the guestfish 'cat' command appends a newline
echo append1:
cat /etc/append1
echo append2:
cat /etc/append2
echo append3:
cat /etc/append3
echo append4:
cat /etc/append4
echo append5:
cat /etc/append5
echo append6:
cat /etc/append6
stat /etc/append6 | grep '^[ug]id:'

echo -----
EOF

if [ "$(cat test-virt-builder.out)" != "true
Hello World
true
true
true
true
-----
HOSTNAME=test.example.com
-----
true
true
/usr/share/zoneinfo/Europe/London
-----
true
root:\$6\$
-----
append1:
hello

append2:
line1
line2

append3:
line1
line2

append4:
line1
line2

append5:
line1

append6:

line2

uid: 1
gid: 1
-----" ]; then
    echo "$0: unexpected output:"
    cat test-virt-builder.out
    exit 1
fi

rm $output
rm test-virt-builder.out
