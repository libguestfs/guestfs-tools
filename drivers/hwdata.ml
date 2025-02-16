(* virt-drivers
 * Copyright (C) 2009-2025 Red Hat Inc.
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

open Printf
open Scanf

module DBKey = struct
  type t =
    | Vendor of int32
    | Device of int32 * int32
  let compare = compare
end
module DB = Map.Make (DBKey)

let is_4_digit_hex id =
  String.length id = 4 &&
  Char.isxdigit id.[0] &&
  Char.isxdigit id.[1] &&
  Char.isxdigit id.[2] &&
  Char.isxdigit id.[3]
let hex_to_int32 id = sscanf id "%lx" identity

(* Loads one of the [*.ids] files, returning the entries as a
 * 3 level map.  Returns [None] if the file could not be opened
 * or parsed.
 *)
let load filename =
  try
    let lines = read_whole_file filename in
    let lines = String.lines_split lines in

    (* This loop drops blank lines and comments, splits the fields of
     * the database, and returns [(lineno, indent, key, label) list].
     *)
    let rec loop lineno acc = function
      | [] -> List.rev acc
      (* Blank lines. *)
      | "" :: lines ->
         loop (lineno+1) acc lines
      (* Note that # only starts a comment at the beginning of the line. *)
      | comment :: lines when String.is_prefix comment "#" ->
         loop (lineno+1) acc lines
      (* Otherwise its some data. *)
      | line :: lines ->
         let len = String.length line in
         let indent =
           let rec counttabs i =
             if i < len && line.[i] = '\t' then 1 + counttabs (i+1) else 0
           in
           counttabs 0 in
         let line = String.sub line indent (len - indent) in

         let n = String.cspan line " \t" in
         let key, label = String.break n line in
         let n = String.span label " \t" in
         let _, label = String.break n label in

         let acc =
           if key = "" && label = "" then acc
           else (lineno, indent, key, label) :: acc in

         loop (lineno+1) acc lines
    in
    let lines = loop 1 [] lines in

    (* Since the format is essentially a space-saving one where
     *   vendor name
     *   \t     device name
     * is short for:
     *   vendor name
     *   vendor device name
     * pull the fields from previous lines down, resulting in
     * a flat list.
     *)
    let rec loop keys acc = function
      | [] -> List.rev acc
      | (lineno, indent, key, label) :: lines ->
         let prefix = List.take indent keys in
         let keys = prefix @ [ key ] in
         let acc = (lineno, keys, label) :: acc in
         loop keys acc lines
    in
    let lines = loop [] [] lines in

    (*
    List.iter (
      fun (lineno, keys, label) ->
        eprintf "[%s] -> %s  # line %d\n"
          (String.concat ";" keys) label lineno
    ) lines;
    *)

    (* Now we can finally process the database.
     *
     * We currently ignore the [C] (class) and other records
     * that appear at the end of the file.  We might want to
     * try parsing these in future.  It will require changes to
     * the code above because the label isn't parsed right.
     *)
    let db =
      List.fold_left (
        fun db (lineno, keys, label) ->
          let loc = filename, lineno in
          match keys with
          | [vendor] when is_4_digit_hex vendor ->
             let vendor = hex_to_int32 vendor in
             DB.add (Vendor vendor) (label, loc) db
          | [vendor; device] when is_4_digit_hex vendor &&
                                  is_4_digit_hex device ->
             let vendor = hex_to_int32 vendor in
             let device = hex_to_int32 device in
             DB.add (Device (vendor, device)) (label, loc) db
          | _ ->
             db
      ) DB.empty lines in

    Some db
  with exn ->
    warning (f_"hwdata: %s: %s") filename (Printexc.to_string exn);
    None

(* Lazily load the PCI database, if present. *)
let pci_db =
  let filename = Hwdata_config.pci_ids in
  lazy (match filename with None -> None | Some filename -> load filename)

(* Look up PCI vendor and device ID. *)
let pci_vendor vendor =
  let db = Lazy.force pci_db in
  match db with
  | None -> None
  | Some db ->
     match DB.find_opt (Vendor vendor) db with
     | None -> None
     | Some (label, _) -> Some label

let pci_device vendor device =
  let db = Lazy.force pci_db in
  match db with
  | None -> None
  | Some db ->
     match DB.find_opt (Device (vendor, device)) db with
     | None -> None
     | Some (label, _) -> Some label

(* Lazily load the USB database, if present. *)
let usb_db =
  let filename = Hwdata_config.usb_ids in
  lazy (match filename with None -> None | Some filename -> load filename)

(* Look up USB vendor and device ID. *)
let usb_vendor vendor =
  let db = Lazy.force usb_db in
  match db with
  | None -> None
  | Some db ->
     match DB.find_opt (Vendor vendor) db with
     | None -> None
     | Some (label, _) -> Some label

let usb_device vendor device =
  let db = Lazy.force usb_db in
  match db with
  | None -> None
  | Some db ->
     match DB.find_opt (Device (vendor, device)) db with
     | None -> None
     | Some (label, _) -> Some label
