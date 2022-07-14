(* virt-sysprep
 * Copyright (C) 2012 Red Hat Inc.
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

open Printf

open Sysprep_operation
open Common_gettext.Gettext

module G = Guestfs

let rec lvm_uuids_perform g root side_effects =
  let typ = g#inspect_get_type root in
  if typ = "linux" then (
    let has_lvm2_feature =
      try g#available [|"lvm2"|]; true with G.Error _ -> false in
    if has_lvm2_feature then (
      let has_pvs, has_vgs = g#pvs () <> [||], g#vgs () <> [||] in
      if has_pvs || has_vgs then (
        try g#vg_activate_all false
        with G.Error _ as exn ->
          (* If the "luks" feature is not available, re-raise the exception. *)
          (try g#available [|"luks"|] with G.Error _ -> raise exn);

          (* Assume VG deactivation failed due to the guest using the
           * FS-on-LUKS-on-LVM scheme.
           *
           * By now, we have unmounted filesystems, but the decrypted LUKS
           * devices still keep the LVs open. Therefore, attempt closing all
           * decrypted LUKS devices that were opened by inspection (i.e., device
           * nodes with pathnames like "/dev/mapper/luks-<uuid>"). Closing the
           * decrypted LUKS devices should remove the references from their
           * underlying LVs, and then VG deactivation should succeed too.
           *
           * Note that closing the decrypted LUKS devices prevents the
           * blockdev-level manipulation of those filesystems that reside on
           * said decrypted LUKS devices, such as the "fs-uuids" operation. But
           * that should be OK, as we order the present operation after all
           * other block device ops.
           *
           * In case the guest uses the FS-on-LVM-on-LUKS scheme, then the
           * original VG deactivation must have failed for a different reason.
           * (As we have unmounted filesystems earlier, and LUKS is below, not
           * on top of, LVM.) The LUKS-closing attempts below will fail then,
           * due to LVM keeping the decrypted LUKS devices open. This failure is
           * harmless and can be considered a no-op. The final, retried VG
           * deactivation should reproduce the original failure.
           *)
          let luks_re = PCRE.compile ("^/dev/mapper/luks" ^
                                      "-[[:xdigit:]]{8}" ^
                                      "(?:-[[:xdigit:]]{4}){3}" ^
                                      "-[[:xdigit:]]{12}$")
          and dmdevs = Array.to_list (g#list_dm_devices ()) in
          let plaintext_devs = List.filter (PCRE.matches luks_re) dmdevs in
          List.iter (fun dev -> try g#cryptsetup_close dev with _ -> ())
            plaintext_devs;
          g#vg_activate_all false
      );
      if has_pvs then g#pvchange_uuid_all ();
      if has_vgs then g#vgchange_uuid_all ();
      if has_pvs || has_vgs then g#vg_activate_all true
    )
  )

let op = {
  defaults with
    order = 99; (* Run it after other block device ops. *)
    name = "lvm-uuids";
    enabled_by_default = true;
    heading = s_"Change LVM2 PV and VG UUIDs";
    pod_description = Some (s_"\
On Linux guests that have LVM2 physical volumes (PVs) or volume groups (VGs),
new random UUIDs are generated and assigned to those PVs and VGs.");
    perform_on_devices = Some lvm_uuids_perform;
}

let () = register_operation op
