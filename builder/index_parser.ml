(* virt-builder
 * Copyright (C) 2013 Red Hat Inc.
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

open Std_utils
open Tools_utils
open Common_gettext.Gettext

open Utils

open Printf
open Unix

let get_index ~downloader ~sigchecker ?(template = false)
      { Sources.uri; proxy } =
  let corrupt_file () =
    error (f_"The index file downloaded from ‘%s’ is corrupt.\n\
              You need to ask the supplier of this file to fix it \
              and upload a fixed version.") uri
  in

  let rec get_index () =
    (* Get the index page. *)
    let tmpfile, _ = Downloader.download downloader ~proxy uri in

    (* Check index file signature (also verifies it was fully
     * downloaded and not corrupted in transit).
     *)
    Sigchecker.verify sigchecker tmpfile;

    (* Try parsing the file. *)
    let sections = Ini_reader.read_ini tmpfile in

    (* Check for repeated os-version+arch combination. *)
    let name_arch_map = List.map (
      fun (n, fields) ->
        let rec find_arch = function
          | ("arch", None, value) :: y -> value
          | _ :: y -> find_arch y
          | [] -> ""
        in
        n, (find_arch fields)
    ) sections in
    let nseen = Hashtbl.create 13 in
    List.iter (
      fun (n, arch) ->
        let id = n, arch in
        if Hashtbl.mem nseen id then (
          eprintf (f_"%s: index is corrupt: os-version ‘%s’ with \
                      architecture ‘%s’ appears two or more times\n")
            prog n arch;
          corrupt_file ()
        );
        Hashtbl.add nseen id true
    ) name_arch_map;

    (* Check for repeated fields. *)
    List.iter (
      fun (n, fields) ->
        let fseen = Hashtbl.create 13 in
        List.iter (
          fun (field, subkey, _) ->
            let hashkey = (field, subkey) in
            if Hashtbl.mem fseen hashkey then (
              (match subkey with
              | Some value ->
                eprintf (f_"%s: index is corrupt: %s: field ‘%s[%s]’ appears \
                            two or more times\n") prog n field value
              | None ->
                eprintf (f_"%s: index is corrupt: %s: field ‘%s’ appears \
                            two or more times\n") prog n field);
              corrupt_file ()
            );
            Hashtbl.add fseen hashkey true
        ) fields
    ) sections;

    (* Turn the sections into the final index. *)
    let entries =
      List.map (
        fun (n, fields) ->
          let fields = List.map (fun (k, sk, v) -> (k, sk), v) fields in
          let printable_name =
            try Some (List.assoc ("name", None) fields)
            with Not_found -> None in
          let osinfo =
            try Some (List.assoc ("osinfo", None) fields)
            with Not_found -> None in
          let file_uri =
            try make_absolute_uri (List.assoc ("file", None) fields)
            with Not_found ->
              eprintf (f_"%s: no ‘file’ (URI) entry for ‘%s’\n") prog n;
            corrupt_file () in
          let arch =
            try Index.Arch (List.assoc ("arch", None) fields)
            with Not_found ->
              if template then
                let g = open_guestfs ~identifier:"template" () in
                g#add_drive_ro file_uri;
                g#launch ();
                let roots = g#inspect_os () in
                let nroots = Array.length roots in
                if nroots <> 1 then (
                  eprintf (f_"%s: no ‘arch’ entry for %s and failed to \
                              guess it\n") prog n;
                  corrupt_file ()
                );
                let inspected_arch = g#inspect_get_arch (Array.get roots 0) in
                g#close();
                Index.GuessedArch inspected_arch
              else (
                eprintf (f_"%s: no ‘arch’ entry for ‘%s’\n") prog n;
                corrupt_file ()
              ) in
          let signature_uri =
            try Some (make_absolute_uri (List.assoc ("sig", None) fields))
            with Not_found -> None in
          let checksum_sha512 =
            try Some (List.assoc ("checksum", Some "sha512") fields)
            with Not_found ->
              try Some (List.assoc ("checksum", None) fields)
              with Not_found -> None in
          let revision =
            try Rev_int (int_of_string (List.assoc ("revision", None) fields))
            with
            | Not_found -> if template then Rev_int 0 else Rev_int 1
            | Failure _ ->
              eprintf (f_"%s: cannot parse ‘revision’ field for ‘%s’\n") prog n;
              corrupt_file () in
          let format =
            try Some (List.assoc ("format", None) fields)
            with Not_found -> None in
          let size =
            let get_image_size filepath =
              (* If a compressed image manages to reach this code, qemu-img just
                 returns a virtual-size equal to actual-size *)
              match detect_file_type filepath with
              | `Unknown ->
                let infos = Utils.get_image_infos filepath in
                JSON_parser.object_get_number "virtual-size" infos
              | `XZ | `GZip | `Tar | ` Zip ->
                eprintf (f_"%s: cannot determine the virtual size of %s \
                            due to compression")
                        prog filepath;
                corrupt_file () in

            try Int64.of_string (List.assoc ("size", None) fields)
            with
            | Not_found ->
              if template then
                get_image_size file_uri
              else (
                eprintf (f_"%s: no ‘size’ field for ‘%s’\n") prog n;
                corrupt_file ()
              )
            | Failure _ ->
              if template then
                get_image_size file_uri
              else (
                eprintf (f_"%s: cannot parse ‘size’ field for ‘%s’\n") prog n;
                corrupt_file ()
              ) in
          let compressed_size =
            try Some (Int64.of_string (List.assoc ("compressed_size", None)
                                         fields))
            with
            | Not_found ->
              None
            | Failure _ ->
              eprintf (f_"%s: cannot parse ‘compressed_size’ field for ‘%s’\n")
                prog n;
              corrupt_file () in
          let expand =
            try Some (List.assoc ("expand", None) fields)
            with Not_found -> None in
          let lvexpand =
            try Some (List.assoc ("lvexpand", None) fields)
            with Not_found -> None in
          let notes =
            let rec loop = function
              | [] -> []
              | (("notes", subkey), value) :: xs ->
                let subkey = match subkey with
                | None -> ""
                | Some v -> v in
                (subkey, value) :: loop xs
              | _ :: xs -> loop xs in
            List.sort (
              fun (k1, _) (k2, _) ->
                String.compare k1 k2
            ) (loop fields) in
          let hidden =
            try bool_of_string (List.assoc ("hidden", None) fields)
            with
            | Not_found -> false
            | Failure _ ->
              eprintf (f_"%s: cannot parse ‘hidden’ field for ‘%s’\n")
                prog n;
              corrupt_file () in
          let aliases =
            let l =
              try String.nsplit " " (List.assoc ("aliases", None) fields)
              with Not_found -> [] in
            match l with
            | [] -> None
            | l -> Some l in

          let checksums =
            match checksum_sha512 with
            | Some c -> Some [Checksums.SHA512 c]
            | None -> None in

          let entry = { Index.printable_name = printable_name;
                        osinfo = osinfo;
                        file_uri = file_uri;
                        arch = arch;
                        signature_uri = signature_uri;
                        checksums = checksums;
                        revision = revision;
                        format = format;
                        size = size;
                        compressed_size = compressed_size;
                        expand = expand;
                        lvexpand = lvexpand;
                        notes = notes;
                        hidden = hidden;
                        aliases = aliases;
                        proxy = proxy;
                        sigchecker = sigchecker } in
          n, entry
      ) sections in

    if verbose () then (
      printf "index file (%s) after parsing (C parser):\n" uri;
      List.iter (Index.print_entry Pervasives.stdout) entries
    );

    entries

  (* Verify same-origin policy for the file= and sig= fields. *)
  and make_absolute_uri path =
    if String.length path = 0 then (
      eprintf (f_"%s: zero length path in the index file\n") prog;
      corrupt_file ()
    )
    else if String.find path "://" >= 0 then (
      eprintf (f_"%s: cannot use a URI (‘%s’) in the index file\n") prog path;
      corrupt_file ()
    )
    else if path.[0] = '/' then (
      eprintf (f_"%s: you must use relative paths (not ‘%s’) \
                  in the index file\n") prog path;
      corrupt_file ()
    )
    else (
      (* Construct the URI. *)
      try
        let i = String.rindex uri '/' in
        String.sub uri 0 (i+1) ^ path
      with
        Not_found -> uri // path
    )
  in

  get_index ()

let write_entry chan (name, { Index.printable_name; file_uri; arch; osinfo;
                              signature_uri; checksums; revision; format; size;
                              compressed_size; expand; lvexpand; notes;
                              aliases; hidden}) =
  let fp fs = fprintf chan fs in
  fp "[%s]\n" name;
  Option.iter (fp "name=%s\n") printable_name;
  Option.iter (fp "osinfo=%s\n") osinfo;
  fp "file=%s\n" file_uri;
  fp "arch=%s\n" (Index.string_of_arch arch);
  Option.iter (fp "sig=%s\n") signature_uri;
  (match checksums with
  | None -> ()
  | Some checksums ->
    List.iter (
      fun c ->
        fp "checksum[%s]=%s\n"
          (Checksums.string_of_csum_t c) (Checksums.string_of_csum c)
    ) checksums
  );
  fp "revision=%s\n" (string_of_revision revision);
  Option.iter (fp "format=%s\n") format;
  fp "size=%Ld\n" size;
  Option.iter (fp "compressed_size=%Ld\n") compressed_size;
  Option.iter (fp "expand=%s\n") expand;
  Option.iter (fp "lvexpand=%s\n") lvexpand;

  let format_notes notes =
    String.concat "\n " (String.nsplit "\n" notes) in

  List.iter (
    fun (lang, notes) ->
      match lang with
      | "" -> fp "notes=%s\n" (format_notes notes)
      | lang -> fp "notes[%s]=%s\n" lang (format_notes notes)
  ) notes;
  (match aliases with
  | None -> ()
  | Some l -> fp "aliases=%s\n" (String.concat " " l)
  );
  if hidden then fp "hidden=true\n";
  fp "\n"
