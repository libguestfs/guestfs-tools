(* virt-builder
 * Copyright (C) 2013-2025 Red Hat Inc.
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

type index = (string * entry) list      (* string = "os-version" *)
and entry = {
  printable_name : string option;       (* the name= field *)
  osinfo : string option;
  file_uri : string;
  arch : arch;
  signature_uri : string option;        (* deprecated, will be removed in 1.26 *)
  checksums : Checksums.csum_t list option;
  revision : Utils.revision;
  format : string option;
  size : int64;
  compressed_size : int64 option;
  expand : string option;
  lvexpand : string option;
  notes : (string * string) list;
  hidden : bool;
  aliases : string list option;

  sigchecker : Sigchecker.t;
  proxy : Curl.proxy;
}
and arch =
  | Arch of string              (** Specified in the metadata. *)
  | GuessedArch of string       (** Guess from inspection data. *)

val string_of_arch : arch -> string
(** [string_of_arch a]Get the string value of [a]. *)

val print_entry : out_channel -> (string * entry) -> unit
(** Debugging helper function dumping an index entry to a stream.
    To write entries for non-debugging purpose, use the
    [Index_parser.write_entry] function. *)
