(* virt-builder
 * Copyright (C) 2014 Red Hat Inc.
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
open Unix

type source = {
  name : string;
  uri : string;
  gpgkey : Utils.gpgkey_type;
  proxy : Curl.proxy;
  format : source_format;
}
and source_format =
| FormatNative
| FormatSimpleStreams

let parse_conf file =
  debug "trying to read %s" file;
  let sections = Ini_reader.read_ini ~error_suffix:"[ignored]" file in

  let sources = List.fold_right (
    fun (n, fields) acc ->
      let give_source n fields =
        let fields = List.map (fun (k, sk, v) -> (k, sk), v) fields in
        let uri =
          try List.assoc ("uri", None) fields
          with Not_found as ex ->
            eprintf (f_"%s: no ‘uri’ entry for ‘%s’ in %s, skipping it\n")
              prog n file;
            raise ex in
        let gpgkey =
          let k =
            try Some (URI.parse_uri (List.assoc ("gpgkey", None) fields)) with
            | Not_found -> None
            | URI.Parse_failed as ex ->
               debug "'%s' has invalid gpgkey URI" n;
               raise ex in
          match k with
          | None -> Utils.No_Key
          | Some uri ->
            (match uri.URI.protocol with
            | "file" -> Utils.KeyFile uri.URI.path
            | _ ->
               debug "'%s' has non-local gpgkey URI" n;
               Utils.No_Key
            ) in
        let proxy =
          try
            (match (List.assoc ("proxy", None) fields) with
            | "no" | "off" -> Curl.UnsetProxy
            | "system" -> Curl.SystemProxy
            | _ as proxy -> Curl.ForcedProxy proxy
            )
          with
            Not_found -> Curl.SystemProxy in
        let format =
          try
            (match (List.assoc ("format", None) fields) with
            | "native" | "" -> FormatNative
            | "simplestreams" -> FormatSimpleStreams
            | fmt ->
               debug "unknown repository type '%s' in %s, skipping it" fmt file;
               invalid_arg fmt
            )
          with
            Not_found -> FormatNative in
        {
          name = n; uri = uri; gpgkey = gpgkey; proxy = proxy;
          format = format;
        }
      in
      try (give_source n fields) :: acc
      with Not_found | Invalid_argument _ -> acc
  ) sections [] in

  debug "read %d sources" (List.length sources);

  sources

let merge_sources current_sources new_sources =
  List.fold_right (
    fun source acc ->
      if List.exists (fun { name = n } -> n = source.name) acc then
        acc
      else
        source :: acc
  ) new_sources current_sources

let filter_filenames filename =
  Filename.check_suffix filename ".conf"

let read_sources () =
  let dirs = Paths.xdg_config_dirs () in
  let dirs =
    match Paths.xdg_config_home () with
    | None -> dirs
    | Some dir -> dir :: dirs in
  let dirs = List.map (fun x -> x // "repos.d") dirs in
  let fnseen = ref StringSet.empty in
  List.fold_left (
    fun acc dir ->
      let files =
        try List.filter filter_filenames (Array.to_list (Sys.readdir dir))
        with Sys_error _ -> [] in
      let files =
        List.filter (fun x -> StringSet.mem x !fnseen <> true) files in
      List.fold_left (
        fun acc file ->
          try (
            let s = merge_sources acc (parse_conf (dir // file)) in
            (* Add the current file name to the set only if its parsing
             * was successful.
             *)
            fnseen := StringSet.add file !fnseen;
            s
          ) with
          | Unix_error (code, fname, _) ->
             debug "file error: %s: %s\n" fname (error_message code);
             acc
          | Invalid_argument msg ->
             debug "internal error: invalid argument: %s" msg;
             acc
      ) acc files
  ) [] dirs
