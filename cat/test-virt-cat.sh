#!/bin/bash -
# libguestfs
# Copyright (C) 2009-2025 Red Hat Inc.
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

# Read out the test files from the image using virt-cat.
if [ "$($VG virt-cat --format=raw -a ../test-data/phony-guests/fedora.img /etc/test1)" != "abcdefg" ]; then
    echo "$0: error: mismatch in file test1"
    exit 1
fi
if [ "$($VG virt-cat --format=raw -a ../test-data/phony-guests/fedora.img /etc/test2)" != "" ]; then
    echo "$0: error: mismatch in file test2"
    exit 1
fi
