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
open Unix_utils
open Common_gettext.Gettext

open Utils

open Printf
open Unix

type t = {
  gpg : string;
  fingerprint : string;
  subkeys_fingerprints : string list;
  check_signature : bool;
  gpghome : string;
  tmpdir : string;
}

(* Import the specified key file. *)
let import_keyfile ~gpg ~gpghome ~tmpdir ?(trust = true) keyfile =
  let status_file = Filename.temp_file ~temp_dir:tmpdir "vbstat" ".txt" in
  let cmd = sprintf "%s --homedir %s --status-file %s --import %s%s"
    gpg gpghome (quote status_file) (quote keyfile)
    (if verbose () then "" else " >/dev/null 2>&1") in
  let r = shell_command cmd in
  if r <> 0 then
    error (f_"could not import public key\n\
              Use the ‘-v’ option and look for earlier error messages.");
  let status = read_whole_file status_file in
  let status = String.nsplit "\n" status in
  let key_id = ref "" in
  let fingerprint = ref "" in
  List.iter (
    fun line ->
      let line = String.nsplit " " line in
      match line with
      | "[GNUPG:]" :: "IMPORT_OK" :: _ :: fp :: _ -> fingerprint := fp
      | "[GNUPG:]" :: "IMPORTED" :: key :: _ -> key_id := key
      | _ -> ()
  ) status;
  if trust then (
    let cmd = sprintf "%s --homedir %s --trusted-key %s --list-keys%s"
      gpg gpghome (quote !key_id)
      (if verbose () then "" else " >/dev/null 2>&1") in
    let r = shell_command cmd in
    if r <> 0 then
      error (f_"GPG failure: could not trust the imported key\n\
                Use the ‘-v’ option and look for earlier error messages.");
  );
  let subkeys =
    (* --with-fingerprint is specified twice so gpg outputs the full
     * fingerprint of the subkeys. *)
    let cmd = sprintf "%s --homedir %s --with-colons \
                       --with-fingerprint --with-fingerprint --list-keys %s%s"
      gpg gpghome !fingerprint
      (if verbose () then "" else " 2>/dev/null") in
    let lines = external_command cmd in
    let current = ref None in
    let subkeys = ref [] in
    List.iter (
      fun line ->
        let line = String.nsplit ":" line in
        match line with
        | "sub" :: ("u"|"-") :: _ :: _ :: id :: _ ->
          current := Some id
        | "fpr" :: _ :: _ :: _ :: _ :: _ :: _ :: _ :: _ :: id :: _ ->
          (match !current with
          | None -> ()
          | Some k ->
            if String.ends_with k id then List.push_front id subkeys;
            current := None
          )
        | _ -> ()
    ) lines;
    !subkeys in
  !fingerprint, subkeys

let rec create ~gpg ~gpgkey ~check_signature ~tmpdir =
  (* Create a temporary directory for gnupg. *)
  let gpgtmpdir = Mkdtemp.temp_dir ~base_dir:tmpdir "vb.gpghome." in
  (* Make sure we have no check_signature=true with no actual key. *)
  let check_signature, gpgkey =
    match check_signature, gpgkey with
    | true, No_Key -> false, No_Key
    | x, y -> x, y in
  let fingerprint, subkeys =
    if check_signature then (
      (* Run gpg so it can setup its own home directory, failing if it
       * cannot.
       *)
      let cmd = sprintf "%s --homedir %s --list-keys%s"
        gpg gpgtmpdir (if verbose () then "" else " >/dev/null 2>&1") in
      let r = shell_command cmd in
      if r <> 0 then
        error (f_"GPG failure: could not run GPG the first time\n\
                  Use the ‘-v’ option and look for earlier error messages.");
      match gpgkey with
      | No_Key ->
        assert false
      | KeyFile kf ->
        import_keyfile gpg gpgtmpdir tmpdir kf
      | Fingerprint fp ->
        let filename = Filename.temp_file ~temp_dir:tmpdir "vbpubkey" ".asc" in
        let cmd = sprintf "%s --yes --armor --output %s --export %s%s"
          gpg (quote filename) (quote fp)
          (if verbose () then "" else " >/dev/null 2>&1") in
        let r = shell_command cmd in
        if r <> 0 then
          error (f_"could not export public key\n\
                    Use the ‘-v’ option and look for earlier error messages.");
        import_keyfile gpg gpgtmpdir tmpdir filename
    ) else
      "", [] in
  {
    gpg = gpg;
    fingerprint = fingerprint;
    subkeys_fingerprints = subkeys;
    check_signature = check_signature;
    gpghome = gpgtmpdir;
    tmpdir = tmpdir;
  }

(* Compare two strings of hex digits ignoring whitespace and case. *)
and equal_fingerprints fp1 fp2 =
  let len1 = String.length fp1 and len2 = String.length fp2 in
  let rec loop i j =
    if i = len1 && j = len2 then true (* match! *)
    else if i = len1 || j = len2 then false (* no match - different lengths *)
    else (
      let x1 = getxdigit fp1.[i] and x2 = getxdigit fp2.[j] in
      match x1, x2 with
      | Some x1, Some x2 when x1 = x2 -> loop (i+1) (j+1)
      | Some x1, Some x2 -> false (* no match - different content *)
      | Some _, None -> loop i (j+1)
      | None, Some _ -> loop (i+1) j
      | None, None -> loop (i+1) (j+1)
    )
  in
  loop 0 0

and getxdigit = function
  | '0'..'9' as c -> Some (Char.code c - Char.code '0')
  | 'a'..'f' as c -> Some (Char.code c - Char.code 'a')
  | 'A'..'F' as c -> Some (Char.code c - Char.code 'A')
  | _ -> None

let verifying_signatures t =
  t.check_signature

let rec verify t filename =
  if t.check_signature then (
    let args = quote filename in
    do_verify t args
  )

and verify_detached t filename sigfile =
  if t.check_signature then (
    match sigfile with
    | None ->
      error (f_"there is no detached signature file\n\
                This probably means the index file is missing a \
                sig=... line.\n\
                You can use --no-check-signature to ignore this error, \
                but that means you are susceptible to \
                man-in-the-middle attacks.")
    | Some sigfile ->
      let args = sprintf "%s %s" (quote sigfile) (quote filename) in
      do_verify t args
  )

and verify_and_remove_signature t filename =
  if t.check_signature then (
    (* Copy the input file as temporary file with the .asc extension,
     * so gpg recognises that format. *)
    let asc_file = Filename.temp_file ~temp_dir:t.tmpdir "vbfile" ".asc" in
    let cmd = [ "cp"; filename; asc_file ] in
    if run_command cmd <> 0 then exit 1;
    let out_file = Filename.temp_file ~temp_dir:t.tmpdir "vbfile" "" in
    let args =
      sprintf "--yes --output %s %s" (quote out_file) (quote filename) in
    do_verify ~verify_only:false t args;
    Some out_file
  ) else
    None

and do_verify ?(verify_only = true) t args =
  let status_file = Filename.temp_file ~temp_dir:t.tmpdir "vbstat" ".txt" in
  let cmd =
    sprintf "%s --homedir %s %s%s --status-file %s %s"
        t.gpg t.gpghome
        (if verify_only then "--verify" else "")
        (if verbose () then "" else " --batch -q --logger-file /dev/null")
        (quote status_file) args in
  let r = shell_command cmd in
  if r <> 0 then
    error (f_"GPG failure: could not verify digital signature of file\n\
              Try:\n - Use the ‘-v’ option and look \
              for earlier error messages.\n\
              - Delete the cache: virt-builder --delete-cache\n\
              - Check no one has tampered with the website or your network!");

  (* Check the fingerprint is who it should be. *)
  let status = read_whole_file status_file in

  let status = String.nsplit "\n" status in
  let fingerprint = ref "" in
  List.iter (
    fun line ->
      let line = String.nsplit " " line in
      match line with
      | "[GNUPG:]" :: "VALIDSIG" :: fp :: _ -> fingerprint := fp
      | _ -> ()
  ) status;

  if not (equal_fingerprints !fingerprint t.fingerprint) &&
    not (List.exists (equal_fingerprints !fingerprint)
           t.subkeys_fingerprints) then
    error (f_"fingerprint of signature does not match the \
              expected fingerprint!\n\
              found fingerprint: %s\n\
              expected fingerprint: %s")
      !fingerprint t.fingerprint
