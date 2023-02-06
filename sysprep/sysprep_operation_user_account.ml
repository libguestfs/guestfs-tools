(* virt-sysprep
 * Copyright (C) 2012 FUJITSU LIMITED
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

open Printf

open Std_utils
open Tools_utils
open Common_gettext.Gettext
open Getopt.OptionName

open Sysprep_operation

module G = Guestfs

let remove_users = ref StringSet.empty
let keep_users = ref StringSet.empty
let add_users set users =
  let users = String.nsplit "," users in
  List.iter (
    function
    | "" ->
      error (f_"user-accounts: empty user name")
    | user ->
      set := StringSet.add user !set
  ) users

let check_remove_user user =
  (* If an user is explicitly excluded, keep it. *)
  if StringSet.mem user !keep_users then
    false
  (* If the list of included users is empty (thus no users were explicitly
   * included), or an user is explicitly included, remove it. *)
  else if StringSet.is_empty !remove_users
      || StringSet.mem user !remove_users then
    true
  (* Any other case, not a reason to remove it. *)
  else
    false

let user_account_perform g root side_effects =
  let typ = g#inspect_get_type root in
  let changed = ref false in
  if typ <> "windows" then (
    g#aug_init "/" 0;
    let uid_min = g#aug_get "/files/etc/login.defs/UID_MIN" in
    let uid_min = int_of_string uid_min in
    let uid_max = g#aug_get "/files/etc/login.defs/UID_MAX" in
    let uid_max = int_of_string uid_max in
    let users = Array.to_list (g#aug_ls "/files/etc/passwd") in
    List.iter (
      fun userpath ->
        let uid = userpath ^ "/uid" in
        let uid = g#aug_get uid in
        let uid = int_of_string uid in
        let username =
          match last_part_of userpath '/' with
          | Some x -> x
          | None -> error "user-accounts: missing '/' in %s" userpath in
        if uid >= uid_min && uid <= uid_max
           && check_remove_user username then (
          changed := true;
          (* Get the home before removing the passwd entry. *)
          let home_dir =
            try Some (g#aug_get (userpath ^ "/home"))
            with _ ->
              if verbose () then
                warning (f_"Cannot get the home directory for %s")
                  username;
              None in
          g#aug_rm userpath;
          g#aug_rm (sprintf "/files/etc/shadow/%s" username);
          g#aug_rm (sprintf "/files/etc/group/%s" username);
          g#rm_rf ("/var/spool/mail/" ^ username);
          match home_dir with
          | None -> ()
          | Some dir -> g#rm_rf dir
        )
    ) users;
    g#aug_save ();
  );
  if !changed then
    side_effects#changed_file ()

let op = {
  defaults with
    name = "user-account";
    enabled_by_default = false;
    heading = s_"Remove the user accounts in the guest";
    pod_description = Some (s_"\
By default remove all the user accounts and their home directories.
The \"root\" account is not removed.

See the I<--remove-user-accounts> parameter for a way to specify
how to remove only some users, or to not remove some others.");
    extra_args = [
      { extra_argspec = [ L"remove-user-accounts" ],
                        Getopt.String (s_"users", add_users remove_users),
                        s_"Users to remove";
        extra_pod_argval = Some "USERS";
        extra_pod_description = s_"\
The user accounts to be removed from the guest.
The value of this option is a list of user names separated by comma,
where specifying an user means it is going to be removed.
For example:

 --remove-user-accounts bob,eve

would only remove the user accounts C<bob> and C<eve>.

This option can be specified multiple times."
      };

      { extra_argspec = [ L"keep-user-accounts" ],
                        Getopt.String (s_"users", add_users keep_users),
                        s_"Users to keep";
        extra_pod_argval = Some "USERS";
        extra_pod_description = s_"\
The user accounts to be kept in the guest.
The value of this option is a list of user names separated by comma,
where specifying an user means it is going to be kept.
For example:

 --keep-user-accounts mary

would keep the user account C<mary>.

This option can be specified multiple times."
      };
    ];
    perform_on_filesystems = Some user_account_perform;
    not_enabled_check_args = fun () ->
      if not (StringSet.is_empty !keep_users) then
        error (f_"user-accounts: --keep-user-accounts parameter was used, \
                  but the \"user-account\" operation is not enabled");
      if not (StringSet.is_empty !remove_users) then
        error (f_"user-accounts: --remove-user-accounts parameter was used, \
                  but the \"user-account\" operation is not enabled");
}

let () = register_operation op
