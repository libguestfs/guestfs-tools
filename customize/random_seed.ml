(* virt-sysprep
 * Copyright (C) 2012-2020 Red Hat Inc.
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

(* It's important that we write a random seed if we possibly can.
 * Unfortunately some installers (hello, Debian) don't include the file
 * in the basic guest, so we have to work out where to create it.
 *)
let rec set_random_seed (g : Guestfs.guestfs) root =
  let typ = g#inspect_get_type root in
  let created = ref false in

  if typ = "linux" then (
    let files = [
      "/var/lib/random-seed";         (* Fedora *)
      "/var/lib/systemd/random-seed"; (* Fedora after F20? *)
      "/var/lib/urandom/random-seed"; (* Debian *)
      "/var/lib/misc/random-seed";    (* SuSE *)
      "/etc/random-seed";             (* CirrOS *)
    ] in
    List.iter (
      fun file ->
        if g#is_file file then (
          make_random_seed_file g file ~exists:true;
          created := true
        )
    ) files;
  );

  if not !created then (
    (* Backup plan: Try to create a new file. *)

    let distro = g#inspect_get_distro root in
    let file =
      match typ, distro with
      | "linux", ("fedora"|"rhel"|"centos"|"scientificlinux"|"oraclelinux"|
                  "rocky"|"redhat-based") ->
        Some "/var/lib/random-seed"
      | "linux", ("debian"|"ubuntu"|"kalilinux") ->
        Some "/var/lib/urandom/random-seed"
      | "linux", ("opensuse"|"sles"|"suse-based") ->
        Some "/var/lib/misc/random-seed"
      | "linux", "cirros" ->
        Some "/etc/random-seed"
      | _ ->
        None in
    match file with
    | Some file ->
      let dir =
        let i = String.rindex file '/' in
        String.sub file 0 i in
      if g#is_dir dir then (
        make_random_seed_file g file;
        created := true
      )
    | None -> ()
  );

  !created

and make_random_seed_file ?exists g file =
  let file_exists =
    match exists with
    | None -> g#is_file file
    | Some b -> b in
  let n =
    if file_exists then (
      let n = Int64.to_int (g#filesize file) in

      (* This file is usually 512 bytes in size.  However during
       * guest creation of some guests it can be just 8 bytes long.
       * Cap the file size to [512, 8192] bytes.
       *)
      min (max n 512) 8192
    )
    else
      (* Default to 512 bytes of randomness. *)
      512 in

  (* Get n bytes of randomness from the host. *)
  let entropy = Urandom.urandom_bytes n in

  if file_exists then (
    (* Truncate the original file and append, in order to
     * preserve original permissions.
     *)
    g#truncate file;
    g#write_append file entropy
  )
  else (
    (* Create a new file, set the permissions restrictively. *)
    g#write file entropy;
    g#chown 0 0 file;
    g#chmod 0o600 file
  )
