#!/bin/bash -
# libguestfs virt-builder Ubuntu cloud-image source test
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
set -e

sources="$top_srcdir/builder/templates/ubuntu-cloud-images"

count=$(awk '$1 == "24.04" && $2 == "x86_64" { count++ } END { print count+0 }' \
            "$sources")
if test "$count" -ne 1; then
    echo "$0: expected exactly one Ubuntu 24.04 x86_64 source"
    exit 1
fi

line=$(awk '$1 == "24.04" && $2 == "x86_64" { print }' "$sources")
read -r version arch format checksum uri <<< "$line"
test "$version" = 24.04
test "$arch" = x86_64
test "$format" = qcow2

if [[ ! "$checksum" =~ ^[0-9a-f]{64}$ ]]; then
    echo "$0: invalid SHA-256: $checksum"
    exit 1
fi

if [[ ! "$uri" =~ ^https://cloud-images\.ubuntu\.com/releases/noble/release-[0-9]{8}/ubuntu-24\.04-server-cloudimg-amd64\.img$ ]]; then
    echo "$0: source is not a dated Canonical Noble amd64 image: $uri"
    exit 1
fi
