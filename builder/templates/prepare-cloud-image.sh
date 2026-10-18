#!/bin/bash -
# libguestfs virt-builder cloud-image preparation helper
# Copyright 2026 Cisco Systems, Inc. and its affiliates
# SPDX-License-Identifier: GPL-2.0-or-later
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
# You should have received a copy of the GNU General Public License along
# with this program; if not, write to the Free Software Foundation, Inc.,
# 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.

export LANG=C
set -euo pipefail

if test "$#" -ne 4; then
    echo "usage: $0 INPUT EXPECTED_SHA256 INPUT_FORMAT OUTPUT" >&2
    exit 2
fi

input=$1
expected=$2
input_format=$3
output=$4

if [[ ! "$expected" =~ ^[0-9a-f]{64}$ ]]; then
    echo "$0: invalid expected SHA-256: $expected" >&2
    exit 2
fi

if [[ ! "$input_format" =~ ^[a-z0-9][a-z0-9._-]*$ ]]; then
    echo "$0: invalid input format: $input_format" >&2
    exit 2
fi

actual=$(sha256sum -- "$input")
actual=${actual%% *}
if test "$actual" != "$expected"; then
    echo "$0: cloud image checksum mismatch" >&2
    echo "$0: expected: $expected" >&2
    echo "$0:   actual: $actual" >&2
    exit 1
fi

temporary_dir=$(mktemp -d -- "${output}.tmp.XXXXXX")
temporary="$temporary_dir/image.raw"
cleanup () {
    rm -rf -- "$temporary_dir"
}
trap cleanup EXIT
trap 'exit 1' HUP INT TERM

qemu-img convert -f "$input_format" -O raw "$input" "$temporary"
mv -f -- "$temporary" "$output"
