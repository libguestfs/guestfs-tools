(* virt-sysprep
 * Copyright (C) 2012-2025 Red Hat Inc.
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License along
 * with this program; if not, write to the Free Software Foundation, Inc.,
 * 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
 *)

open Sysprep_operation
open Common_gettext.Gettext

module G = Guestfs

let system_devices_file = "/etc/lvm/devices/system.devices"

let rec lvm_system_devices_perform g root side_effects =
  let typ = g#inspect_get_type root in
  if typ = "linux" then g#rm_f system_devices_file

let op = {
  defaults with
    name = "lvm-system-devices";
    enabled_by_default = true;
    heading = s_"Remove LVM2 system.devices file";
    pod_description =
      Some (s_"On Linux guests, LVM2's scanning for physical volumes (PVs) may \
               be restricted to those block devices whose WWIDs are listed in \
               C<" ^ system_devices_file ^ ">.  When cloning VMs, WWIDs may \
               change, breaking C<lvm pvscan>.  Remove \
               C<" ^ system_devices_file ^ ">.");
    perform_on_filesystems = Some lvm_system_devices_perform;
}

let () = register_operation op
