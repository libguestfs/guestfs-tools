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

open Common_gettext.Gettext
open Sysprep_operation

let glob = "/etc/NetworkManager/system-connections/*.nmconnection"

let net_nmconn_perform (g : Guestfs.guestfs) root side_effects =
  let typ = g#inspect_get_type root in
  let distro = g#inspect_get_distro root in
  match typ, distro with
  | "linux", ("fedora"|"rhel"|"centos"|"scientificlinux"|"oraclelinux"|
              "redhat-based") -> Array.iter g#rm_f (g#glob_expand glob)
  | _ -> ()

let op = {
  defaults with
    name = "net-nmconn";
    enabled_by_default = true;
    heading = s_"Remove system-local NetworkManager connection profiles \
      (keyfiles)";
    pod_description = Some (s_"On Fedora and Red Hat Enterprise Linux, remove \
      the C<" ^ glob ^ "> files.");
    perform_on_filesystems = Some net_nmconn_perform;
}

let () = register_operation op
