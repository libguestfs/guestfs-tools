(* virt-dib
 * Copyright (C) 2015 Red Hat Inc.
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

open Cmdline
open Utils
open Elements

open Printf

module G = Guestfs

let checksums = [ "md5"; "sha256" ]
and tool_of_checksum csum =
  csum ^ "sum"

let exclude_elements elements = function
  | [] ->
    (* No elements to filter out, so just don't bother iterating through
     * the elements. *)
    elements
  | excl -> StringSet.filter (not_in_list excl) elements

let read_envvars envvars =
  List.filter_map (
    fun var ->
      let i = String.find var "=" in
      if i = -1 then (
        try Some (var, Sys.getenv var)
        with Not_found -> None
      ) else (
        let len = String.length var in
        Some (String.sub var 0 i, String.sub var (i + 1) (len - i - 1))
      )
  ) envvars

let read_dib_envvars () =
  let vars = Array.to_list (Unix.environment ()) in
  let vars = List.filter (fun x -> String.is_prefix x "DIB_") vars in
  let vars = List.map (fun x -> x ^ "\n") vars in
  String.concat "" vars

let write_script fn text =
  with_open_out fn (
    fun oc ->
      output_string oc text;
      flush oc
  );
  Unix.chmod fn 0o755

let envvars_string l =
  let l = List.map (
    fun (var, value) ->
      sprintf "export %s=%s" var (quote value)
  ) l in
  String.concat "\n" l

let prepare_external ~envvars ~dib_args ~dib_vars ~out_name ~root_label
  ~rootfs_uuid ~image_cache ~arch ~network ~debug ~fs_type ~checksum
  ~python
  destdir libdir fakebindir loaded_elements all_elements element_paths =
  let network_string = if network then "" else "1" in
  let checksum_string = if checksum then "1" else "" in
  let elements_paths_yaml =
    List.map (
      fun e ->
        sprintf "%s: %s" e (quote (Hashtbl.find loaded_elements e).directory)
    ) (StringSet.elements all_elements) in
  let elements_paths_yaml = String.concat ", " elements_paths_yaml in
  let elements_paths_array =
    List.map (
      fun e ->
        sprintf "[%s]=%s" e (quote (Hashtbl.find loaded_elements e).directory)
    ) (StringSet.elements all_elements) in
  let elements_paths_array = String.concat " " elements_paths_array in

  let run_extra = sprintf "\
#!/bin/bash
set -e
%s
mount_dir=$1
shift
hooks_dir=$1
shift
target_dir=$1
shift
script=$1
shift

VIRT_DIB_OURPATH=$(dirname $(realpath $0))

# user variables
%s

export PATH=%s:$PATH

# d-i-b variables
export TMP_MOUNT_PATH=\"$mount_dir\"
export DIB_OFFLINE=%s
export IMAGE_NAME=\"%s\"
export DIB_ROOT_LABEL=\"%s\"
export DIB_IMAGE_ROOT_FS_UUID=%s
export DIB_IMAGE_CACHE=\"%s\"
export _LIB=%s
export ARCH=%s
export TMP_HOOKS_PATH=\"$hooks_dir\"
export DIB_ARGS=\"%s\"
export IMAGE_ELEMENT=\"%s\"
export ELEMENTS_PATH=\"%s\"
export DIB_ENV=%s
export TMPDIR=\"${TMP_MOUNT_PATH}/tmp\"
export TMP_DIR=\"${TMPDIR}\"
export DIB_DEBUG_TRACE=%d
export FS_TYPE=%s
export DIB_CHECKSUM=%s
export DIB_PYTHON_EXEC=%s

elinfo_out=$(<${VIRT_DIB_OURPATH}/elinfo_out)
eval \"$elinfo_out\"

ENVIRONMENT_D_DIR=$target_dir/../environment.d

if [ -d $ENVIRONMENT_D_DIR ] ; then
    env_files=$(find $ENVIRONMENT_D_DIR -maxdepth 1 -xtype f | \
        grep -E \"/[0-9A-Za-z_\\.-]+$\" | \
        LANG=C sort -n)
    for env_file in $env_files ; do
        source $env_file
    done
fi

source $_LIB/die

$target_dir/$script
"
    (if debug >= 1 then "set -x\n" else "")
    (envvars_string envvars)
    fakebindir
    network_string
    out_name
    root_label
    rootfs_uuid
    image_cache
    (quote libdir)
    arch
    dib_args
    (String.concat " " (StringSet.elements all_elements))
    (String.concat ":" element_paths)
    (quote dib_vars)
    debug
    fs_type
    checksum_string
    python in
  write_script (destdir // "run-part-extra.sh") run_extra;
  let elinfo_out = sprintf "\
export IMAGE_ELEMENT_YAML=\"{%s}\"
function get_image_element_array {
  echo \"%s\"
};
export -f get_image_element_array;
"
    elements_paths_yaml
    elements_paths_array in
  write_script (destdir // "elinfo_out") elinfo_out

let prepare_aux ~envvars ~dib_args ~dib_vars ~log_file ~out_name ~rootfs_uuid
  ~arch ~network ~root_label ~install_type ~debug ~extra_packages ~fs_type
  ~checksum destdir all_elements =
  let network_string = if network then "" else "1" in
  let checksum_string = if checksum then "1" else "" in

  let script_run_part = sprintf "\
#!/bin/bash
set -e
%s
sysroot=$1
shift
mysysroot=$1
shift
blockdev=$1
shift
target_dir=$1
shift
new_wd=$1
shift
script=$1
shift

# user variables
%s

# system variables
export HOME=$mysysroot/tmp/in_target.aux/perm/home
export PATH=$mysysroot/tmp/in_target.aux/hooks/bin:$PATH
export TMP=$mysysroot/tmp
export TMPDIR=$TMP
export TMP_DIR=$TMP

# d-i-b variables
export TMP_MOUNT_PATH=$sysroot
export TARGET_ROOT=$sysroot
export DIB_OFFLINE=%s
export IMAGE_NAME=\"%s\"
export DIB_IMAGE_ROOT_FS_UUID=%s
export DIB_IMAGE_CACHE=$HOME/.cache/image-create
export DIB_ROOT_LABEL=\"%s\"
export _LIB=$mysysroot/tmp/in_target.aux/lib
export _PREFIX=$mysysroot/tmp/in_target.aux/elements
export ARCH=%s
export TMP_HOOKS_PATH=$mysysroot/tmp/in_target.aux/hooks
export DIB_ARGS=\"%s\"
export DIB_MANIFEST_SAVE_DIR=\"$mysysroot/tmp/in_target.aux/out/${IMAGE_NAME}.d\"
export IMAGE_BLOCK_DEVICE=$blockdev
export IMAGE_BLOCK_DEVICE_WITHOUT_PART=$(echo ${IMAGE_BLOCK_DEVICE} | sed -e \"s|^\\(.*loop[0-9]*\\)p[0-9]*$|\\1|g\")
export IMAGE_ELEMENT=\"%s\"
export DIB_ENV=%s
export DIB_DEBUG_TRACE=%d
export DIB_NO_TMPFS=1
export FS_TYPE=%s
export DIB_CHECKSUM=%s

export TMP_BUILD_DIR=$mysysroot/tmp/in_target.aux
export TMP_IMAGE_DIR=$mysysroot/tmp/in_target.aux

if [ -n \"$mysysroot\" ]; then
  export PATH=$mysysroot/tmp/in_target.aux/fake-bin:$PATH
  source $_LIB/die
else
  export PATH=\"$PATH:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin\"
fi

ENVIRONMENT_D_DIR=$target_dir/../environment.d

if [ -d $ENVIRONMENT_D_DIR ] ; then
    env_files=$(find $ENVIRONMENT_D_DIR -maxdepth 1 -xtype f | \
        grep -E \"/[0-9A-Za-z_\\.-]+$\" | \
        LANG=C sort -n)
    for env_file in $env_files ; do
        source $env_file
    done
fi

if [ -n \"$new_wd\" ]; then
  cd \"$mysysroot/$new_wd\"
fi

$target_dir/$script
"
    (if debug >= 1 then "set -x\n" else "")
    (envvars_string envvars)
    network_string
    out_name
    rootfs_uuid
    root_label
    arch
    dib_args
    (String.concat " " (StringSet.elements all_elements))
    (quote dib_vars)
    debug
    fs_type
    checksum_string in
  write_script (destdir // "run-part.sh") script_run_part;
  let script_run_and_log = "\
#!/bin/bash
logfile=$1
shift
exec 3>&1
exit `( ( ( $(dirname $0)/run-part.sh \"$@\" ) 2>&1 3>&-; echo $? >&4) | tee -a $logfile >&3 >&2) 4>&1`
" in
  write_script (destdir // "run-and-log.sh") script_run_and_log;

  (* Create the fake sudo support. *)
  do_mkdir (destdir // "fake-bin");
  let fake_sudo = "\
#!/bin/bash
set -e

SCRIPTNAME=fake-sudo

ARGS_SHORT=\"EHiu:\"
ARGS_LONG=\"\"
TEMP=`POSIXLY_CORRECT=1 getopt ${ARGS_SHORT:+-o $ARGS_SHORT} ${ARGS_LONG:+--long $ARGS_LONG} \
     -n \"$SCRIPTNAME\" -- \"$@\"`
if [ $? != 0 ]; then echo \"$SCRIPTNAME: terminating...\" >&2 ; exit 1 ; fi
eval set -- \"$TEMP\"

preserve_env=
set_home=
login_shell=
user=

while true; do
  case \"$1\" in
    -E) preserve_env=1; shift;;
    -H) set_home=1; shift;;
    -i) login_shell=1; shift;;
    -u) user=$2; shift 2;;
    --) shift; break;;
    *) echo \"$SCRIPTNAME: internal arguments error\"; exit 1;;
  esac
done

if [ -n \"$user\" ]; then
  if [ $user != root -a $user != `whoami` ]; then
    echo \"$SCRIPTNAME: cannot use the sudo user $user, only root and $(whoami) handled\" >&2
    exit 1
  fi
fi

if [ -z \"$preserve_env\" ]; then
  for envvar in `awk 'BEGIN{for (i in ENVIRON) {print i}}'`; do
    case \"$envvar\" in
      PATH | USER | USERNAME | HOSTNAME | TERM | LANG | HOME | SHELL | LOGNAME ) ;;
      BASH_FUNC_* ) unset -f $envvar ;;
      *) unset $envvar ;;
    esac
  done
fi
# TMPDIR needs to be unset, regardless of -E
unset TMPDIR
# ... and do that also to the other \"TMPDIR\"-like variables
unset TMP
unset TMP_DIR

cmd=$1
shift
$cmd \"$@\"
" in
  write_script (destdir // "fake-bin" // "sudo") fake_sudo;
  (* Pick dib-run-parts from the host, if available, otherwise put
   * a fake executable which will error out if used.
   *)
  (try
    let loc = which "dib-run-parts" in
    do_cp loc (destdir // "fake-bin")
  with Executable_not_found _ ->
    let fake_dib_run_parts = "\
#!/bin/sh
echo \"Please install dib-run-parts on the host\"
exit 1
" in
    write_script (destdir // "fake-bin" // "dib-run-parts") fake_dib_run_parts;
  );

  (* Write the custom hooks. *)
  let script_install_type_env = sprintf "\
export DIB_DEFAULT_INSTALLTYPE=${DIB_DEFAULT_INSTALLTYPE:-\"%s\"}
"
    install_type in
  write_script (destdir // "hooks" // "environment.d" // "11-dib-install-type.bash") script_install_type_env;

  (* Write install-packages.sh if needed. *)
  if extra_packages <> [] then (
    let script_install_packages = sprintf "\
#!/bin/bash
install-packages %s
"
      (String.concat " " extra_packages) in
    write_script (destdir // "install-packages.sh") script_install_packages;
  );

  do_mkdir (destdir // "perm")

let timing_output ~target_name entries timings =
  let buf = Buffer.create 4096 in
  Buffer.add_string buf "----------------------- PROFILING -----------------------\n";
  Buffer.add_char buf '\n';
  bprintf buf "Target: %s\n" target_name;
  Buffer.add_char buf '\n';
  bprintf buf "%-40s %9s\n" "Script" "Seconds";
  bprintf buf "%-40s %9s\n" "---------------------------------------" "----------";
  Buffer.add_char buf '\n';
  List.iter (
    fun x ->
      bprintf buf "%-40s %10.3f\n" x (Hashtbl.find timings x);
  ) entries;
  Buffer.add_char buf '\n';
  Buffer.add_string buf "--------------------- END PROFILING ---------------------\n";
  Buffer.contents buf

type sysroot_type =
  | In
  | Out
  | Subroot

let timed_run fn =
  let time_before = Unix.gettimeofday () in
  fn ();
  let time_after = Unix.gettimeofday () in
  time_after -. time_before

let run_parts ~debug ~sysroot ~blockdev ~log_file ?(new_wd = "")
  (g : Guestfs.guestfs) hook_name scripts =
  let hook_dir = "/tmp/in_target.aux/hooks/" ^ hook_name in
  let scripts = List.sort digit_prefix_compare scripts in
  let outbuf = Buffer.create 16384 in
  let timings = Hashtbl.create 13 in
  let new_wd =
    match sysroot, new_wd with
    | (Out|Subroot), "" -> "''"
    | (In|Out|Subroot), dir -> dir in
  List.iter (
    fun x ->
      message (f_"Running: %s/%s") hook_name x;
      g#write_append log_file (sprintf "Running %s/%s...\n" hook_name x);
      let out = ref "" in
      let run () =
        let outstr =
          match sysroot with
          | In ->
            g#sh (sprintf "/tmp/in_target.aux/run-and-log.sh '%s' '' '' '%s' '%s' '%s' '%s'" log_file blockdev hook_dir new_wd x)
          | Out ->
            g#debug "sh" [| "/sysroot/tmp/in_target.aux/run-and-log.sh"; "/sysroot" ^ log_file; "/sysroot"; "/sysroot"; blockdev; "/sysroot" ^ hook_dir; new_wd; x |]
          | Subroot ->
            g#debug "sh" [| "/sysroot/tmp/in_target.aux/run-and-log.sh"; "/sysroot" ^ log_file; "/sysroot/subroot"; "/sysroot"; blockdev; "/sysroot" ^ hook_dir; new_wd; x |] in
        out := outstr;
        Buffer.add_string outbuf outstr in
      let delta_t = timed_run run in
      Buffer.add_char outbuf '\n';
      out := ensure_trailing_newline !out;
      printf "%s%!" !out;
      if debug >= 1 then (
        printf "%s completed after %.3f s\n" x delta_t
      );
      Hashtbl.add timings x delta_t;
  ) scripts;
  g#write_append log_file (timing_output ~target_name:hook_name scripts timings);
  flush_all ();
  Buffer.contents outbuf

let run_parts_host ~debug (g : Guestfs.guestfs) hook_name base_mount_dir scripts run_script =
  let scripts = List.sort digit_prefix_compare scripts in
  let mount_dir = base_mount_dir // hook_name in
  (* Point to the in-guest hooks, so that changes there can affect
   * other phases.
   *)
  let hooks_dir = mount_dir // "tmp" // "in_target.aux" // "hooks" in
  let hook_dir = hooks_dir // hook_name in
  do_mkdir mount_dir;

  let rec fork_and_run () =
    let pid = Unix.fork () in
    if pid = 0 then ( (* child *)
      let retcode = run_scripts () in
      flush_all ();
      let cmd = [ "guestunmount"; mount_dir ] in
      ignore (run_command cmd);
      Exit._exit retcode
    );
    pid
  and run_scripts () =
    let timings = Hashtbl.create 13 in
    let rec loop = function
      | x :: xs ->
        message (f_"Running: %s/%s") hook_name x;
        let cmd = [ run_script; mount_dir; hooks_dir; hook_dir; x ] in
        let retcode = ref 0 in
        let run () =
          retcode := run_command cmd in
        let delta_t = timed_run run in
        if debug >= 1 then (
          printf "\n";
          printf "%s completed after %.3f s\n" x delta_t
        );
        Hashtbl.add timings x delta_t;
        let retcode = !retcode in
        if retcode <> 0 then retcode
        else loop xs
      | [] -> 0
    in
    let retcode = loop scripts in
    if debug >= 1 then (
      print_string (timing_output ~target_name:hook_name scripts timings)
    );
    retcode
  in

  g#mount_local mount_dir;
  let pid = fork_and_run () in
  g#mount_local_run ();

  (match snd (Unix.waitpid [] pid) with
  | Unix.WEXITED 0 -> ()
  | Unix.WEXITED i -> exit i
  | Unix.WSIGNALED i
  | Unix.WSTOPPED i ->
    error (f_"sub-process killed by signal (%d)") i
  );

  flush_all ()

let run_install_packages ~debug ~blockdev ~log_file
  (g : Guestfs.guestfs) packages =
  let pkgs_string = String.concat " " packages in
  message (f_"Installing: %s") pkgs_string;
  g#write_append log_file (sprintf "Installing %s...\n" pkgs_string);
  let out = g#sh (sprintf "/tmp/in_target.aux/run-and-log.sh '%s' '' '' '%s' '/tmp/in_target.aux' '' 'install-packages.sh'" log_file blockdev) in
  let out = ensure_trailing_newline out in
  if debug >= 1 then (
    printf "%s%!" out;
    printf "package installation completed\n";
  );
  flush_all ();
  out

(* Finalize the list of output formats. *)
let () = Output_format.bake ()

let main () =
  let cmdline = parse_cmdline () in
  let debug = cmdline.debug in

  (* Check that the specified base directory of diskimage-builder
   * has the "die" script in it, so we know the directory is the
   * right one (hopefully so, at least).
   *)
  if not (Sys.file_exists (cmdline.basepath // "die")) then
    error (f_"the specified base path is not the diskimage-builder library");

  (* Check for required tools. *)
  let python =
    match cmdline.python with
    | None -> get_required_tool "python"
    | Some exe -> exe in
  require_tool "uuidgen";
  Output_format.check_formats_prerequisites cmdline.formats;
  if cmdline.checksum then
    List.iter (fun x -> require_tool (tool_of_checksum x)) checksums;

  let image_basename = Filename.basename cmdline.image_name in
  let image_basename_d = image_basename ^ ".d" in

  let tmpdir = Mkdtemp.temp_dir "dib." in
  On_exit.rm_rf tmpdir;
  let auxtmpdir = tmpdir // "in_target.aux" in
  do_mkdir auxtmpdir;
  let hookstmpdir = auxtmpdir // "hooks" in
  do_mkdir (hookstmpdir // "environment.d");    (* Just like d-i-b does. *)
  do_mkdir (auxtmpdir // "out" // image_basename_d);
  let elements =
    if cmdline.use_base then ["base"] @ cmdline.elements
    else cmdline.elements in
  let elements =
    if cmdline.is_ramdisk then [cmdline.ramdisk_element] @ elements
    else elements in
  info (f_"Elements: %s") (String.concat " " elements);
  if debug >= 1 then (
    printf "tmpdir: %s\n" tmpdir;
    printf "element paths: %s\n" (String.concat ":" cmdline.element_paths);
  );

  let loaded_elements = load_elements ~debug cmdline.element_paths in
  if debug >= 1 then (
    printf "loaded elements:\n";
    Hashtbl.iter (
      fun k v ->
        printf "  %s => %s\n" k v.directory;
        Hashtbl.iter (
          fun k v ->
            printf "\t%-20s %s\n" k (String.concat " " (List.sort compare v))
        ) v.hooks;
    ) loaded_elements;
    printf "\n";
  );
  let all_elements = load_dependencies elements loaded_elements in
  let all_elements = exclude_elements all_elements
    (cmdline.excluded_elements @ builtin_elements_blacklist) in

  info (f_"Expanded elements: %s")
       (String.concat " " (StringSet.elements all_elements));

  let envvars = read_envvars cmdline.envvars in
  info (f_"Carried environment variables: %s")
       (String.concat " " (List.map fst envvars));
  if debug >= 1 then (
    printf "carried over envvars:\n";
    if envvars <> [] then
      List.iter (
        fun (var, value) ->
          printf "  %s=%s\n" var value
      ) envvars
    else
      printf "  (none)\n";
    printf "\n";
  );
  let dib_args = stringify_args (Array.to_list Sys.argv) in
  let dib_vars = read_dib_envvars () in
  if debug >= 1 then (
    printf "DIB args:\n%s\n" dib_args;
    printf "DIB envvars:\n%s\n" dib_vars
  );

  message (f_"Preparing auxiliary data");

  copy_elements all_elements loaded_elements
    (cmdline.excluded_scripts @ builtin_scripts_blacklist) hookstmpdir;

  (* Re-read the hook scripts from the hooks dir, as d-i-b (and we too)
   * has basically copied over anything found in elements.
   *)
  let final_hooks = load_hooks ~debug hookstmpdir in

  let log_file = "/tmp/in_target.aux/perm/" ^ (log_filename ()) in

  let arch =
    match cmdline.arch with
    | "" -> current_arch ()
    | arch -> arch in

  let root_label =
    match cmdline.root_label with
    | None ->
      (* XFS has a limit of 12 characters for filesystem labels.
       * Not changing the default for other filesystems to maintain
       * backwards compatibility.
       *)
      (match cmdline.fs_type with
      | "xfs" -> "img-rootfs"
      | _ -> "cloudimg-rootfs")
    | Some label -> label in

  let image_cache =
    match cmdline.image_cache with
    | None -> Sys.getenv "HOME" // ".cache" // "image-create"
    | Some dir -> dir in
  do_mkdir image_cache;

  let rootfs_uuid = uuidgen () in

  prepare_aux ~envvars ~dib_args ~dib_vars ~log_file ~out_name:image_basename
              ~rootfs_uuid ~arch ~network:cmdline.network ~root_label
              ~install_type:cmdline.install_type ~debug
              ~extra_packages:cmdline.extra_packages
              ~fs_type:cmdline.fs_type
              ~checksum:cmdline.checksum
              auxtmpdir all_elements;

  let delete_output_file = ref cmdline.delete_on_failure in
  let delete_file () =
    if !delete_output_file then (
      let filenames = Output_format.get_filenames cmdline.formats cmdline.image_name in
      List.iter (
        fun fn ->
          try Unix.unlink fn with _ -> ()
      ) filenames
    )
  in
  at_exit delete_file;

  prepare_external ~envvars ~dib_args ~dib_vars ~out_name:image_basename
                   ~root_label ~rootfs_uuid ~image_cache ~arch
                   ~network:cmdline.network ~debug
                   ~fs_type:cmdline.fs_type
                   ~checksum:cmdline.checksum
                   ~python
                   tmpdir cmdline.basepath
                   (auxtmpdir // "fake-bin")
                   loaded_elements all_elements cmdline.element_paths;

  let run_hook ~blockdev ~sysroot ?(new_wd = "") (g : Guestfs.guestfs) hook =
    try
      let scripts =
        (* Sadly, scripts (especially in root.d and extra-data.d)
         * can add (by copying or symlinking) new scripts for other
         * phases, which would be ignored if we were using the lists
         * collected after composing the tree of hooks.
         * As result, when running in-chroot hooks, re-read the list
         * of scripts actually available for each hook.
         *)
        match hook with
        | "pre-install.d" | "install.d" | "post-install.d" | "finalise.d" ->
          let scripts_path = "/tmp/in_target.aux/hooks/" ^ hook in
          (* Cleanly handle cases when the phase directory does not exist. *)
          if g#is_dir ~followsymlinks:true scripts_path then
            load_scripts g scripts_path
          else
            raise Not_found
        | _ ->
          Hashtbl.find final_hooks hook in
      if debug >= 1 then (
        printf "Running hooks for %s...\n%!" hook;
      );
      run_parts ~debug ~sysroot ~blockdev ~log_file ~new_wd g hook scripts
    with Not_found -> "" in

  let copy_in (g : Guestfs.guestfs) srcdir destdir =
    let desttar = Filename.temp_file ~temp_dir:tmpdir "virt-dib." ".tar.gz" in
    let cmd = [ "tar"; "czf"; desttar; "-C"; srcdir; "--owner=root";
                "--group=root"; "." ] in
    if run_command cmd <> 0 then exit 1;
    g#mkdir_p destdir;
    g#tar_in ~compress:"gzip" desttar destdir;
    Sys.remove desttar in

  if debug >= 1 then
    ignore (run_command [ "tree"; "-ps"; tmpdir ]);

  message (f_"Opening the disks");

  let is_ramdisk_build =
    cmdline.is_ramdisk || StringSet.mem "ironic-agent" all_elements in

  let g, tmpdisk, tmpdiskfmt, drive_partition =
    let g = open_guestfs () in
    Option.may g#set_memsize cmdline.memsize;
    Option.may g#set_smp cmdline.smp;
    g#set_network cmdline.network;

    (* Main disk with the built image. *)
    let fmt = "raw" in
    let fn =
      (* If "raw" is among the selected outputs, use it as main backing
       * disk, otherwise create a temporary disk.
       *)
      if not is_ramdisk_build && Output_format.set_mem "raw" cmdline.formats then
        cmdline.image_name
      else
        Filename.temp_file ~temp_dir:tmpdir "image." "" in
    let fn = output_filename fn fmt in
    (* Produce the output image. *)
    g#disk_create fn fmt cmdline.size;
    g#add_drive ~readonly:false ~format:fmt fn;

    (* Helper drive for elements and binaries. *)
    g#add_drive_scratch (unit_GB 5);

    (match cmdline.drive with
    | None ->
      g#add_drive_scratch (unit_GB 5)
    | Some drive ->
      g#add_drive ?format:cmdline.drive_format drive;
    );

    g#launch ();

    Output_format.check_formats_appliance_prerequisites cmdline.formats g;

    (* Prepare the /in_target.aux partition. *)
    g#mkfs "ext2" "/dev/sdb";
    g#mount "/dev/sdb" "/";

    copy_in g auxtmpdir "/";
    copy_in g cmdline.basepath "/lib";
    g#umount "/";

    (* Prepare the /in_target.aux/perm partition. *)
    let drive_partition =
      match cmdline.drive with
      | None ->
        g#mkfs "ext2" "/dev/sdc";
        "/dev/sdc"
      | Some _ ->
        let partitions = Array.to_list (g#list_partitions ()) in
        (match partitions with
        | [] -> "/dev/sdc"
        | p ->
          let p = List.filter (fun x -> String.is_prefix x "/dev/sdc") p in
          if p = [] then
            error (f_"no partitions found in the helper drive");
          List.hd p
        ) in
    g#mount drive_partition "/";
    g#mkdir_p "/home/.cache/image-create";
    g#umount "/";

    g, fn, fmt, drive_partition in

  let mount_aux () =
    g#mkmountpoint "/tmp/in_target.aux";
    g#mount "/dev/sdb" "/tmp/in_target.aux";
    g#mount drive_partition "/tmp/in_target.aux/perm" in

  (* Small kludge: try to umount all first: if that fails, use lsof and fuser
   * to find out what might have caused the failure, run udevadm to try
   * to settle things down (udev, you never know), and try umount all again.
   *)
  let checked_umount_all () =
    try g#umount_all ()
    with G.Error _ ->
      if debug >= 1 then (
        (try printf "lsof:\n%s\nEND\n" (g#debug "sh" [| "lsof"; "/sysroot"; |]) with _ -> ());
        (try printf "fuser:\n%s\nEND\n" (g#debug "sh" [| "fuser"; "-v"; "-m"; "/sysroot"; |]) with _ -> ());
        (try printf "losetup:\n%s\nEND\n" (g#debug "sh" [| "losetup"; "--list"; "--all" |]) with _ -> ());
      );
      ignore (g#debug "sh" [| "udevadm"; "--debug"; "settle" |]);
      g#umount_all () in

  g#mkmountpoint "/tmp";
  mount_aux ();

  let blockdev =
    (* Setup a loopback device, just like d-i-b would tie an image in the host
     * environment.
     *)
    let run_losetup device =
      let lines = g#debug "sh" [| "losetup"; "--show"; "-f"; device |] in
      let lines = String.nsplit "\n" lines in
      let lines = List.filter ((<>) "") lines in
      (match lines with
      | [] -> device
      | x :: _ -> x
      ) in
    let blockdev = run_losetup "/dev/sda" in

    let run_hook_out_eval hook envvar =
      let lines = run_hook ~sysroot:Out ~blockdev g hook in
      let lines = String.nsplit "\n" lines in
      let lines = List.filter ((<>) "") lines in
      if lines = [] then None
      else (try Some (var_from_lines envvar lines) with _ -> None) in

    (match run_hook_out_eval "block-device.d" "IMAGE_BLOCK_DEVICE" with
    | None -> blockdev
    | Some x -> x
    ) in

  let rec run_hook_out ?(new_wd = "") hook =
    do_run_hooks_noout ~sysroot:Out ~new_wd hook
  and run_hook_in hook =
    do_run_hooks_noout ~sysroot:In hook
  and run_hook_subroot hook =
    do_run_hooks_noout ~sysroot:Subroot hook
  and do_run_hooks_noout ~sysroot ?(new_wd = "") hook =
    ignore (run_hook ~sysroot ~blockdev ~new_wd g hook)
  and run_hook_host hook =
    try
      let scripts = Hashtbl.find final_hooks hook in
      if debug >= 1 then (
        printf "Running hooks for %s...\n%!" hook;
      );
      run_parts_host ~debug g hook tmpdir scripts
        (tmpdir // "run-part-extra.sh")
    with Not_found -> () in

  g#sync ();
  checked_umount_all ();
  flush_all ();

  message (f_"Setting up the destination root");

  (* Create and mount the target filesystem. *)
  let mkfs_options =
    match cmdline.mkfs_options with
    | None -> []
    | Some o -> [ o ] in
  let mkfs_options =
    [ "-t"; cmdline.fs_type ] @
    (match cmdline.fs_type with
    | "ext4" ->
      (* Very conservative to handle images being resized a lot
       * Without -J option specified, default journal size will be set to 32M
       * and online resize will be failed with error of needs too many credits.
       *)
      [ "-i"; "4096"; "-J"; "size=64" ]
    | _ -> []
    ) @ mkfs_options @ [ blockdev ] in
  ignore (g#debug "sh" (Array.of_list ([ "mkfs" ] @ mkfs_options)));
  g#set_label blockdev root_label;
  if String.is_prefix cmdline.fs_type "ext" then
    g#set_uuid blockdev rootfs_uuid;
  g#mount blockdev "/";
  g#mkmountpoint "/tmp";
  mount_aux ();
  g#mkdir "/subroot";

  run_hook_subroot "root.d";

  g#sync ();
  g#umount "/tmp/in_target.aux/perm";
  g#umount "/tmp/in_target.aux";
  g#rm_rf "/tmp";
  let subroot_items =
    let l = Array.to_list (g#ls "/subroot") in
    let l_lost_plus_found, l = List.partition ((=) "lost+found") l in
    if l_lost_plus_found <> [] then (
      g#rm_rf "/subroot/lost+found";
    );
    l in
  List.iter (fun x -> g#mv ("/subroot/" ^ x) ("/" ^ x)) subroot_items;
  g#rmdir "/subroot";
  (* Check /tmp exists already. *)
  ignore (g#is_dir "/tmp");
  mount_aux ();
  g#ln_s "in_target.aux/hooks" "/tmp/in_target.d";

  run_hook_host "extra-data.d";

  run_hook_in "pre-install.d";

  if cmdline.extra_packages <> [] then
    ignore (run_install_packages ~debug ~blockdev ~log_file g
                                 cmdline.extra_packages);

  run_hook_in "install.d";

  run_hook_in "post-install.d";

  (* Unmount and remount the image, as d-i-b does at this point too. *)
  g#sync ();
  checked_umount_all ();
  flush_all ();
  g#mount blockdev "/";
  (* Check /tmp/in_target.aux still exists. *)
  ignore (g#is_dir "/tmp/in_target.aux");
  g#mount "/dev/sdb" "/tmp/in_target.aux";
  g#mount drive_partition "/tmp/in_target.aux/perm";

  run_hook_in "finalise.d";

  let out_dir = "/tmp/in_target.aux/out/" ^ image_basename_d in

  run_hook_out ~new_wd:out_dir "cleanup.d";

  g#sync ();

  if g#ls out_dir <> [||] then (
    message (f_"Extracting data out of the image");
    do_mkdir (cmdline.image_name ^ ".d");
    g#copy_out out_dir (Filename.dirname cmdline.image_name);
  );

  (* Unmount everything, and remount only the root to cleanup
   * its /tmp; this way we should be pretty sure that there is
   * nothing left mounted over /tmp, so it is safe to empty it.
   *)
  checked_umount_all ();
  flush_all ();
  g#mount blockdev "/";
  Array.iter (fun x -> g#rm_rf ("/tmp/" ^ x)) (g#ls "/tmp");
  (* Truncate /var/log files in preparation for first boot. *)
  truncate_recursive g "/var/log";
  let non_log fn =
    not (String.is_suffix fn ".log")
  in
  (* Remove root logs. *)
  rm_rf_only_files g ~filter:non_log "/root";

  flush_all ();

  Output_format.run_formats_on_filesystem cmdline.formats g cmdline.image_name tmpdir;

  message (f_"Umounting the disks");

  (* Now that we've finished the build, don't delete the output file on
   * exit.
   *)
  delete_output_file := false;

  g#sync ();
  checked_umount_all ();
  g#shutdown ();
  g#close ();

  flush_all ();

  (* Don't produce images as output when doing a ramdisk build. *)
  if not is_ramdisk_build then
    Output_format.run_formats_on_file cmdline.formats cmdline.image_name (tmpdisk, tmpdiskfmt) tmpdir;

  if not is_ramdisk_build && cmdline.checksum then (
    let file_flags = [ Unix.O_WRONLY; Unix.O_CREAT; Unix.O_TRUNC; ] in
    let filenames = Output_format.get_filenames cmdline.formats cmdline.image_name in
    List.iter (
      fun fn ->
        message (f_"Generating checksums for %s") fn;
        let cmds =
          List.map (
            fun csum ->
              let csum_fn = fn ^ "." ^ csum in
              let csum_tool = tool_of_checksum csum in
              let outfd = Unix.openfile csum_fn file_flags 0o640 in
              [ csum_tool; fn ], Some outfd, None
          ) checksums in
        let res = run_commands cmds in
        List.iteri (
          fun i code ->
            if code <> 0 then (
              let args, _, _ = List.nth cmds i in
              error (f_"external command ‘%s’ exited with error %d")
                (List.hd args) code
            )
        ) res;
    ) filenames;
  );

  message (f_"Done")

let () = run_main_and_handle_errors main
