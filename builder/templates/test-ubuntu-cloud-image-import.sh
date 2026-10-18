#!/bin/bash -
# libguestfs virt-builder Ubuntu cloud-image import test
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

if ! command -v qemu-img >/dev/null 2>&1; then
    echo "$0: qemu-img is not installed; skipping" >&2
    exit 77
fi

if ! command -v sha256sum >/dev/null 2>&1; then
    echo "$0: sha256sum is not installed; skipping" >&2
    exit 77
fi

helper="$top_srcdir/builder/templates/prepare-cloud-image.sh"
tmpdir=$(mktemp -d)
trap 'rm -rf -- "$tmpdir"' EXIT

source_raw="$tmpdir/source.raw"
input="$tmpdir/input.qcow2"
output="$tmpdir/output.raw"
bad_output="$tmpdir/bad-output.raw"
failed_output="$tmpdir/conversion-failure.raw"

truncate -s 8M "$source_raw"
printf 'virt-builder cloud-image import test\n' | \
    dd of="$source_raw" conv=notrunc status=none
printf 'nonzero data beyond the first block\n' | \
    dd of="$source_raw" bs=1 seek=4194304 conv=notrunc status=none
qemu-img convert -f raw -O qcow2 "$source_raw" "$input"
checksum=$(sha256sum -- "$input")
checksum=${checksum%% *}

"$helper" "$input" "$checksum" qcow2 "$output"

info=$(qemu-img info --output=json "$output" | tr -d '[:space:]')
case "$info" in
    *'"format":"raw"'*) ;;
    *) echo "$0: converted image is not raw" >&2; exit 1 ;;
esac
case "$info" in
    *'"virtual-size":8388608'*) ;;
    *) echo "$0: converted image has the wrong virtual size" >&2; exit 1 ;;
esac

qemu-img compare -f raw -F raw "$source_raw" "$output"

bad_checksum=$(printf '%064d' 0)
if "$helper" "$input" "$bad_checksum" qcow2 "$bad_output"; then
    echo "$0: incorrect checksum unexpectedly succeeded" >&2
    exit 1
fi
if test -e "$bad_output"; then
    echo "$0: checksum failure left an output image" >&2
    exit 1
fi

printf 'existing output must survive conversion failure\n' > "$failed_output"
failed_checksum=$(sha256sum -- "$failed_output")
failed_checksum=${failed_checksum%% *}
if "$helper" "$input" "$checksum" not-a-format "$failed_output"; then
    echo "$0: invalid input format unexpectedly converted" >&2
    exit 1
fi
actual_failed_checksum=$(sha256sum -- "$failed_output")
actual_failed_checksum=${actual_failed_checksum%% *}
if test "$actual_failed_checksum" != "$failed_checksum"; then
    echo "$0: conversion failure changed an existing output" >&2
    exit 1
fi
if find "$tmpdir" -maxdepth 1 -name 'conversion-failure.raw.tmp.*' \
        -print -quit | grep -q .; then
    echo "$0: conversion failure left temporary files" >&2
    exit 1
fi
