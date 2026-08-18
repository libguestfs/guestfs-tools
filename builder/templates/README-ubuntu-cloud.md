<!--
Copyright 2026 Cisco Systems, Inc. and its affiliates
SPDX-License-Identifier: GPL-2.0-or-later
-->

# Ubuntu cloud-image templates

Ubuntu 24.04 does not publish the Debian Installer tree used by the historical
`virt-install` and preseed workflow in `make-template.ml`.  It therefore uses
a pinned Canonical cloud image as its input.

The generator downloads a dated QCOW2 image, verifies its pinned SHA-256,
converts it to sparse raw format, and then reuses the existing inspection,
post-installation, sysprep, sparsify, compression, and index-generation path.
After the general sysprep pass, it explicitly runs the machine-ID operation
last because sysprep's late customization step can populate an empty
`/etc/machine-id`.  The downloaded image is not committed to this repository.

The offline import helper test covers digest rejection, payload-preserving
QCOW2-to-raw conversion, and conversion cleanup.  It does not replace the
full generator, inspection, sysprep, index, firmware, or boot validation.

## Updating the pinned image

1. Select a dated release from <https://cloud-images.ubuntu.com/releases/>.
2. Download the image, `SHA256SUMS`, and `SHA256SUMS.gpg` from the same
   directory.
3. Verify the signed checksum file using the Ubuntu cloud-image keyring and
   then verify the image:

       gpgv --keyring /usr/share/keyrings/ubuntu-cloudimage-keyring.gpg \
         SHA256SUMS.gpg SHA256SUMS
       grep ' \*ubuntu-24.04-server-cloudimg-amd64.img$' SHA256SUMS | \
         sha256sum -c -

4. Update the dated URL and SHA-256 in `ubuntu-cloud-images`.
5. Run `make check`, generate the template, validate its generated index
   fragment, and boot-test both the default image and an expanded image on
   x86_64 KVM.

The final template build, generated index fragment, catalog signature, and
publication must all refer to the same image bytes.  Signing keys and the
published template binary do not belong in this source repository.

## Preliminary source-state inspection

The signed root-filesystem artifact from the same pinned Canonical release was
inspected before image generation.  It has an empty `/etc/machine-id`, no SSH
host keys, no `/var/lib/cloud` instance state, and no persistent netplan file.
The root password is locked.  The `ubuntu` account is not pre-created;
cloud-init remains enabled and declares `ubuntu` as its default first-boot
user.  These findings must be confirmed against the generated QCOW2-derived
template, because the root-filesystem artifact is supporting evidence rather
than the final input image.

## Required validation before publication

The source-only change does not decide these image-policy questions.  Before
publishing an Ubuntu 24.04 template, validate and document:

- whether the Canonical image boots with BIOS, UEFI, or both;
- whether its 3.5 GiB virtual size should remain the template default or its
  root filesystem should be expanded to the historical 6 GiB default;
- whether cloud-init should remain enabled and create its default `ubuntu`
  account, including behavior when no datasource is present; and
- the generated template still has an empty machine ID, no SSH host keys, and
  no stale cloud-init instance state before first boot.
