(* virt-customize
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

open Unix
open Printf

open Std_utils
open Tools_utils
open Common_gettext.Gettext

open Customize_cmdline
open Password
open Append_line

module G = Guestfs

let run (g : G.guestfs) root (ops : ops) =
  (* Based on the guest type, choose a log file location. *)
  let logfile =
    match g#inspect_get_type root with
    | "windows" | "dos" ->
      if g#is_dir ~followsymlinks:true "/Temp" then "/Temp/builder.log"
      else "/builder.log"
    | _ ->
      if g#is_dir ~followsymlinks:true "/tmp" then "/tmp/builder.log"
      else "/builder.log" in

  (* Function to cat the log file, for debugging and error messages. *)
  let debug_logfile () =
    try g#download logfile "/dev/stderr"
    with exn ->
      warning (f_"log file %s: %s (ignored)") logfile (Printexc.to_string exn) in

  (* Useful wrapper for scripts. *)
  let do_run ~display ?(warn_failed_no_network = false) cmd =
    let incompatible_fn () =
      let guest_arch = g#inspect_get_arch root in
      error (f_"host cpu (%s) and guest arch (%s) are not compatible, so you cannot use command line options that involve running commands in the guest.  Use --firstboot scripts instead.")
            Guestfs_config.host_cpu guest_arch
    in

    try
      run_in_guest_command g root ~logfile ~incompatible_fn cmd
    with
      G.Error msg ->
        debug_logfile ();
        if warn_failed_no_network && not (g#get_network ()) then (
          prerr_newline ();
          warning (f_"the command may have failed because the network is disabled.  Try either removing ‘--no-network’ or adding ‘--network’ on the command line.");
          prerr_newline ()
        );
        error (f_"%s: command exited with an error") display
  in

  let guest_pkgs_command f =
    try f (g#inspect_get_package_management root) with
    | Guest_packages.Unknown_package_manager msg
    | Guest_packages.Unimplemented_package_manager msg ->
      error "%s" msg
  in

  (* Set the random seed. *)
  message (f_"Setting a random seed");
  if not (Random_seed.set_random_seed g root) then
    warning (f_"random seed could not be set for this type of guest");

  (* Set the systemd machine ID.  This must be set before performing
   * --install/--update since (at least in Fedora) the kernel %post
   * script requires a machine ID and will fail if it is not set.
   *)
  let () =
    let etc_machine_id = "/etc/machine-id" in
    let statbuf =
      try Some (g#lstatns etc_machine_id) with G.Error _ -> None in
    (match statbuf with
     | Some { G.st_size = 0L; G.st_mode = mode }
          when (Int64.logand mode 0o170000_L) = 0o100000_L ->
        message (f_"Setting the machine ID in %s") etc_machine_id;
        let id = Urandom.urandom_bytes 16 in
        let id = String.map_chars (fun c -> sprintf "%02x" (Char.code c)) id in
        let id = String.concat "" id in
        let id = id ^ "\n" in
        g#write etc_machine_id id
     | _ -> ()
    ) in

  (* Store the passwords and set them all at the end. *)
  let passwords = Hashtbl.create 13 in
  let set_password user pw =
    if Hashtbl.mem passwords user then
      error (f_"multiple --root-password/--password options set the password for user ‘%s’ twice") user;
    Hashtbl.replace passwords user pw
  in

  (* Perform the remaining customizations in command-line order. *)
  List.iter (
    function
    | `AppendLine (path, line) ->
       (* It's an error if it's not a single line.  This is
        * to prevent incorrect line endings being added to a file.
        *)
       if String.contains line '\n' then
         error (f_"--append-line: line must not contain newline characters.  Use the --append-line option multiple times to add several lines.");

       message (f_"Appending line to %s") path;
       append_line g root path line

    | `Chmod (mode, path) ->
      message (f_"Changing permissions of %s to %s") path mode;
      (* If the mode string is octal, add the OCaml prefix for octal values
       * so it is properly converted as octal integer.
       *)
      let mode = if String.is_prefix mode "0" then "0o" ^ mode else mode in
      g#chmod (int_of_string mode) path

    | `Command cmd ->
      message (f_"Running: %s") cmd;
      do_run ~display:cmd cmd

    | `CommandsFromFile _ ->
      (* Nothing to do, the files with customize commands are already
       * read when their arguments are met. *)
      ()

    | `Copy (src, dest) ->
      message (f_"Copying (in image): %s to %s") src dest;
      g#cp_a src dest

    | `CopyIn (localpath, remotedir) ->
      message (f_"Copying: %s to %s") localpath remotedir;
      g#copy_in localpath remotedir

    | `Delete path ->
      message (f_"Deleting: %s") path;
      Array.iter g#rm_rf (g#glob_expand ~directoryslash:false path)

    | `Edit (path, expr) ->
      message (f_"Editing: %s") path;

      if not (g#exists path) then
        error (f_"%s does not exist in the guest") path;

      if not (g#is_file ~followsymlinks:true path) then
        error (f_"%s is not a regular file in the guest") path;

      Perl_edit.edit_file g#ocaml_handle path expr

    | `FirstbootCommand cmd ->
      message (f_"Installing firstboot command: %s") cmd;
      Firstboot.add_firstboot_script g root cmd cmd

    | `FirstbootPackages pkgs ->
      message (f_"Installing firstboot packages: %s")
        (String.concat " " pkgs);
      let cmd = guest_pkgs_command (Guest_packages.install_command pkgs) in
      let name = String.concat " " ("install" :: pkgs) in
      Firstboot.add_firstboot_script g root name cmd

    | `FirstbootScript script ->
      message (f_"Installing firstboot script: %s") script;
      let cmd = read_whole_file script in
      Firstboot.add_firstboot_script g root script cmd

    | `Hostname hostname ->
      message (f_"Setting the hostname: %s") hostname;
      if not (Hostname.set_hostname g root hostname) then
        warning (f_"hostname could not be set for this type of guest")

    | `InstallPackages pkgs ->
      message (f_"Installing packages: %s") (String.concat " " pkgs);
      let cmd = guest_pkgs_command (Guest_packages.install_command pkgs) in
      do_run ~display:cmd ~warn_failed_no_network:true cmd

    | `Link (target, links) ->
      List.iter (
        fun link ->
          message (f_"Linking: %s -> %s") link target;
          g#ln_sf target link
      ) links

    | `Mkdir dir ->
      message (f_"Making directory: %s") dir;
      g#mkdir_p dir

    | `Move (src, dest) ->
      message (f_"Moving: %s -> %s") src dest;
      g#mv src dest

    | `Password (user, pw) ->
      set_password user pw

    | `RootPassword pw ->
      set_password "root" pw

    | `Script script ->
      message (f_"Running: %s") script;
      let cmd = read_whole_file script in
      do_run ~display:script cmd

    | `Scrub path ->
      message (f_"Scrubbing: %s") path;
      g#scrub_file path

    | `SMAttach pool ->
      (match pool with
      | Subscription_manager.PoolAuto ->
        message (f_"Attaching to compatible subscriptions");
        let cmd = "subscription-manager attach --auto" in
        do_run ~display:cmd ~warn_failed_no_network:true cmd
      | Subscription_manager.PoolId id ->
        message (f_"Attaching to the pool %s") id;
        let cmd = sprintf "subscription-manager attach --pool=%s" (quote id) in
        do_run ~display:cmd ~warn_failed_no_network:true cmd
      )

    | `SMRegister ->
      message (f_"Registering with subscription-manager");
      let creds =
        match ops.flags.sm_credentials with
        | None ->
          error (f_"subscription-manager credentials required for --sm-register")
        | Some c -> c in
      let cmd = sprintf "subscription-manager register --username=%s --password=%s"
                  (quote creds.Subscription_manager.sm_username)
                  (quote creds.Subscription_manager.sm_password) in
      do_run ~display:"subscription-manager register"
             ~warn_failed_no_network:true cmd

    | `SMRemove ->
      message (f_"Removing all the subscriptions");
      let cmd = "subscription-manager remove --all" in
      do_run ~display:cmd ~warn_failed_no_network:true cmd

    | `SMUnregister ->
      message (f_"Unregistering with subscription-manager");
      let cmd = "subscription-manager unregister" in
      do_run ~display:cmd ~warn_failed_no_network:true cmd

    | `SSHInject (user, selector) ->
      if unix_like (g#inspect_get_type root) then (
        message (f_"SSH key inject: %s") user;
        Ssh_key.do_ssh_inject_unix g user selector
      ) else
        warning (f_"SSH key could not be injected for this type of guest")

    | `Truncate path ->
      message (f_"Truncating: %s") path;
      g#truncate path

    | `TruncateRecursive path ->
      message (f_"Recursively truncating: %s") path;
      truncate_recursive g path

    | `Timezone tz ->
      message (f_"Setting the timezone: %s") tz;
      if not (Timezone.set_timezone g root tz) then
        warning (f_"timezone could not be set for this type of guest")

    | `Touch path ->
      message (f_"Running touch: %s") path;
      g#touch path

    | `UninstallPackages pkgs ->
      message (f_"Uninstalling packages: %s") (String.concat " " pkgs);
      let cmd = guest_pkgs_command (Guest_packages.uninstall_command pkgs) in
      do_run ~display:cmd cmd

    | `Update ->
      message (f_"Updating packages");
      let cmd = guest_pkgs_command Guest_packages.update_command in
      do_run ~display:cmd ~warn_failed_no_network:true cmd

    | `Upload (path, dest) ->
      message (f_"Uploading: %s to %s") path dest;
      let dest =
        if g#is_dir ~followsymlinks:true dest then
          dest ^ "/" ^ Filename.basename path
        else
          dest in
      (* Do the file upload. *)
      g#upload path dest;

      (* Copy (some of) the permissions from the local file to the
       * uploaded file.
       *)
      let statbuf = stat path in
      let perms = statbuf.st_perm land 0o7777 (* sticky & set*id *) in
      g#chmod perms dest;
      let uid, gid = statbuf.st_uid, statbuf.st_gid in
      let chown () =
        try g#chown uid gid dest
        with G.Error m as e ->
          if g#last_errno () = G.Errno.errno_EPERM
          then warning "%s" m
          else raise e in
      chown ()

    | `Write (path, content) ->
      message (f_"Writing: %s") path;
      g#write path content
  ) ops.ops;

  (* Set all the passwords at the end. *)
  if Hashtbl.length passwords > 0 then (
    match g#inspect_get_type root with
    | "linux" ->
      message (f_"Setting passwords");
      let password_crypto = ops.flags.password_crypto in
      set_linux_passwords ?password_crypto g root passwords

    | _ ->
      warning (f_"passwords could not be set for this type of guest")
  );

  if not ops.flags.no_selinux_relabel then (
    message (f_"SELinux relabelling");
    SELinux_relabel.relabel g
  );

  (* Clean up the log file:
   *
   * If debugging, dump out the log file.
   * Then if asked, scrub the log file.
   *)
  if verbose () then debug_logfile ();
  if ops.flags.scrub_logfile && g#exists logfile then (
    message (f_"Scrubbing the log file");

    (* Try various methods with decreasing complexity. *)
    try g#scrub_file logfile
    with _ -> g#rm_f logfile
  );

  (* Kill any daemons (eg. started by newly installed packages) using
   * the sysroot.
   * XXX How to make this nicer?
   * XXX fuser returns an error if it doesn't kill any processes, which
   * is not very useful.
   *)
  (try ignore (g#debug "sh" [| "fuser"; "-k"; "/sysroot" |])
   with exn ->
     if verbose () then
       warning (f_"%s (ignored)") (Printexc.to_string exn)
  );
  g#ping_daemon () (* tiny delay after kill *)
