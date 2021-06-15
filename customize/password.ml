(* virt-sysprep
 * Copyright (C) 2012-2021 Red Hat Inc.
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

type password_crypto = [ `MD5 | `SHA256 | `SHA512 | `YESCRYPT ]

type password_selector = {
  pw_password : password;
  pw_locked : bool;
}
and password =
| Password of string
| Random_password
| Disabled_password

type password_map = (string, password_selector) Hashtbl.t

let make_random_password =
  (* Get random characters from the set [A-Za-z0-9] with some
   * homoglyphs removed.
   *)
  let chars = "ABCDEFGHIJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz0123456789" in
  fun () -> Urandom.urandom_uniform 16 chars

let password_crypto_of_string = function
  | "md5" -> `MD5
  | "sha256" -> `SHA256
  | "sha512" -> `SHA512
  | "yescrypt" -> `YESCRYPT
  | arg ->
    error (f_"password-crypto: unknown algorithm %s, use \"md5\", \"sha256\", \"sha512\" or \"yescrypt\"") arg

let rec parse_selector arg =
  parse_selector_list arg (String.nsplit ":" arg)

and parse_selector_list orig_arg = function
  | [ "lock"|"locked" ] ->
    { pw_locked = true; pw_password = Disabled_password }
  | ("lock"|"locked") :: rest ->
    let pw = parse_selector_list orig_arg rest in
    { pw with pw_locked = true }
  | [ "file"; filename ] ->
    { pw_password = Password (read_first_line_from_file filename);
      pw_locked = false }
  | "password" :: password ->
    { pw_password = Password (String.concat ":" password); pw_locked = false }
  | [ "random" ] ->
    { pw_password = Random_password; pw_locked = false }
  | [ "disable"|"disabled" ] ->
    { pw_password = Disabled_password; pw_locked = false }
  | _ ->
    error (f_"invalid password selector ‘%s’; see the man page") orig_arg

(* Permissible characters in a salt. *)
let chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789./"

let rec set_linux_passwords ?password_crypto (g : Guestfs.guestfs) root passwords =
  let crypto =
    match password_crypto with
    | None -> default_crypto g root
    | Some c -> c in

  (* Create a (almost) empty temporary file with the attributes of
   * /etc/shadow, so we can restore them later.
   *)
  let tempfile = g#mktemp "/etc/shadow.guestfsXXXXXX" in
  g#write tempfile "*";
  g#copy_attributes ~all:true "/etc/shadow" tempfile;

  g#aug_init "/" 0;
  let users = Array.to_list (g#aug_ls "/files/etc/shadow") in
  List.iter (
    fun userpath ->
      let user =
        match last_part_of userpath '/' with
        | Some x -> x
        | None -> error "password: missing '/' in %s" userpath in
      try
        (* Each line is: "user:[!!]password:..."
         * !! at the front of the password field means the account is locked.
         *)
        let selector = Hashtbl.find passwords user in
        let pwfield =
          match selector with
          | { pw_locked = locked;
              pw_password = Password password } ->
            (if locked then "!!" else "") ^ encrypt password crypto
          | { pw_locked = locked;
              pw_password = Random_password } ->
            let password = make_random_password () in
            info (f_"Setting random password of %s to %s") user password;
            (if locked then "!!" else "") ^ encrypt password crypto
          | { pw_locked = true; pw_password = Disabled_password } -> "!!*"
          | { pw_locked = false; pw_password = Disabled_password } -> "*" in
        g#aug_set (userpath ^ "/password") pwfield
      with Not_found -> ()
  ) users;
  g#aug_save ();
  g#aug_close ();

  (* Restore all the attributes from the temporary file, and remove it. *)
  g#copy_attributes ~all:true tempfile "/etc/shadow";
  g#rm tempfile

(* Encrypt each password.  Use glibc (on the host).  See:
 * https://rwmj.wordpress.com/2013/07/09/setting-the-root-or-other-passwords-in-a-linux-guest/
 *)
and encrypt password crypto =
  (* Get random characters from the set [A-Za-z0-9./]
   *
   * 24 characters gives a 144 bits (18 bytes) salt.  Unlike the more
   * traditional 128 bits (16 bytes) salt, this 144 bits salt is always
   * represented by the same number of base64 characters without any
   * padding issues, where 128 bits can be represented by 22 or 23
   * (depending on padding) base64-encoded characters, even with a
   * non-standard base64 encoding scheme.
   *
   * We need it this way, because the yescrypt hashing methods requires
   * at least 128 bits of salt to work properly.
   *)
  let salt = Urandom.urandom_uniform 24 chars in
  let salt =
    (match crypto with
    | `MD5 -> "$1$"
    | `SHA256 -> "$5$"
    | `SHA512 -> "$6$"
    | `YESCRYPT -> "$y$j9T$") ^ salt ^ "$" in
  let r = Crypt.crypt password salt in
  (*printf "password: encrypt %s with salt %s -> %s\n" password salt r;*)
  r

(* glibc 2.7 was released in Oct 2007.  Approximately, all guests that
 * precede this date only support md5, whereas all guests after this
 * date can support sha512.
 *
 * Most distros released in 2020 or later ship with libxcrypt >= 4.3,
 * and are able to handle yescrypt hashes.
 *)
and default_crypto g root =
  let distro = g#inspect_get_distro root in
  let major = g#inspect_get_major_version root in
  match distro, major with
  | ("rhel"|"centos"|"scientificlinux"|"oraclelinux"|"redhat-based"), v when v >= 9 ->
    `YESCRYPT
  | ("rhel"|"centos"|"scientificlinux"|"oraclelinux"|"redhat-based"), v when v >= 6 ->
    `SHA512
  | ("rhel"|"centos"|"scientificlinux"|"oraclelinux"|"redhat-based"), _ ->
    `MD5 (* RHEL 5 does not appear to support SHA512, according to crypt(3) *)

  | "fedora", v when v >= 30 -> `YESCRYPT
  | "fedora", v when v >= 9 -> `SHA512
  | "fedora", _ -> `MD5

  | "debian", v when v >= 11 -> `YESCRYPT
  | "debian", v when v >= 5 -> `SHA512
  | "debian", _ -> `MD5

  | "ubuntu", v when v >= 20 -> `YESCRYPT
  | "ubuntu", v when v >= 10 -> `SHA512
  | "ubuntu", _ -> `MD5

  | ("opensuse"|"sles"), v when v >= 15 -> `YESCRYPT
  | ("opensuse"|"sles"), v when v >= 11 -> `SHA512
  | ("opensuse"|"sles"), _ -> `MD5

  (* Rolling distributions, which hopefully should be updated enough. *)
  | ("archlinux"|"kalilinux"), _ -> `YESCRYPT
  | ("voidlinux"), _ -> `SHA512

  | _, _ ->
    let minor = g#inspect_get_minor_version root in
    warning (f_"password: using insecure md5 password encryption for guest of type %s version %d.%d.
If this is incorrect, use --password-crypto option and file a bug.")
      distro major minor;
    `MD5
