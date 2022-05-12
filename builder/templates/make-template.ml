#!/usr/bin/env ocaml
(* libguestfs
 * Copyright (C) 2016-2022 Red Hat Inc.
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
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
 *)

(* This script is used to create the virt-builder templates hosted
 * http://libguestfs.org/download/builder/
 *
 * Prior to November 2016, the templates were generated using
 * shell scripts located in libguestfs.git/builder/website.
 *)

#load "str.cma";;
#load "unix.cma";;
#directory "+guestfs";; (* use globally installed guestfs *)
#load "mlguestfs.cma";;

open Printf

let windows_installers = "/mnt/media/installers/Windows"

let prog = "make-template"

(* Ensure that a file is deleted on exit. *)
let unlink_on_exit =
  let files = ref [] in
  at_exit (
    fun () -> List.iter (fun f -> try Unix.unlink f with _ -> ()) !files
  );
  fun file -> files := file :: !files

let () =
  (* Check we are being run from the correct directory. *)
  if not (Sys.file_exists "debian.preseed") then (
    eprintf "%s: run this script from the builder/templates subdirectory\n"
            prog;
    exit 1
  );

  (* Check that the ./run script was used. *)
  (try ignore (Sys.getenv "VIRT_BUILDER_DIRS")
   with Not_found ->
     eprintf "%s: you must use `../../run ./make-template.ml ...' to run this script\n"
             prog;
     exit 1
  );

  (* Check we're not being run as root. *)
  if Unix.geteuid () = 0 then (
    eprintf "%s: don't run this script as root\n" prog;
    exit 1
  );
  (* ... and that LIBVIRT_DEFAULT_URI=qemu:///system is NOT set,
   * which is the same as above.
   *)
  let s = try Sys.getenv "LIBVIRT_DEFAULT_URI" with Not_found -> "" in
  if s = "qemu:///system" then (
    eprintf "%s: don't set LIBVIRT_DEFAULT_URI=qemu:///system\n" prog;
    exit 1
  )
  ;;

type os =
  | Alma of int * int           (* major, minor *)
  | CentOS of int * int         (* major, minor *)
  | CentOSStream of int         (* major *)
  | RHEL of int * int
  | Debian of int * string      (* version, dist name like "wheezy" *)
  | Ubuntu of string * string
  | Fedora of int               (* version number *)
  | FreeBSD of int * int        (* major, minor *)
  | Windows of int * int * windows_variant (* major, minor, variant *)
and windows_variant = Client | Server
type arch = X86_64 | Aarch64 | Armv7 | I686 | PPC64 | PPC64le | S390X

type boot_media =
  | Location of string          (* virt-install --location (preferred) *)
  | CDRom of string             (* downloaded CD-ROM *)

let quote = Filename.quote
let (//) = Filename.concat

let rec main () =
  assert (Sys.word_size = 64);
  Random.self_init ();

  (* Parse the command line. *)
  let os, arch = parse_cmdline () in

  (* Choose a disk size for this OS. *)
  let virtual_size_gb = get_virtual_size_gb os arch in

  (* For OSes which require a kickstart, this generates one.
   * For OSes which require a preseed file, this returns one (we
   * don't generate preseed files at the moment).
   * For Windows this returns an unattend file in an ISO.
   * For OSes which cannot be automated (FreeBSD), this returns None.
   *)
  let ks = make_kickstart os arch in

  (* Find the boot media.  Normally ‘virt-install --location’ but
   * for FreeBSD it downloads the boot ISO.
   *)
  let boot_media = make_boot_media os arch in

  (* Choose a random temporary name for the libvirt domain. *)
  let tmpname = sprintf "tmp-%s" (random8 ()) in

  (* Choose a random temporary disk name. *)
  let tmpout = sprintf "%s.img" tmpname in
  unlink_on_exit tmpout;

  (* Create the final output name (actually not quite final because
   * we will xz-compress it).
   *)
  let output = filename_of_os os arch "" in

  (* Some architectures need EFI boot. *)
  let tmpefivars =
    if needs_uefi os arch then (
      let code, vars =
        match arch with
        | X86_64 ->
           "/usr/share/edk2/ovmf/OVMF_CODE.fd",
           "/usr/share/edk2/ovmf/OVMF_VARS.fd"
        | Aarch64 ->
           "/usr/share/edk2/aarch64/QEMU_EFI-pflash.raw",
           "/usr/share/edk2/aarch64/vars-template-pflash.raw"
        | Armv7 ->
           "/usr/share/edk2/arm/QEMU_EFI-pflash.raw",
           "/usr/share/edk2/arm/vars-template-pflash.raw"
        | _ -> assert false in

      let vars_out = Sys.getcwd () // sprintf "%s.vars" tmpname in
      unlink_on_exit vars_out;
      let cmd = sprintf "cp %s %s" (quote vars) (quote vars_out) in
      if Sys.command cmd <> 0 then exit 1;
      Some (code, vars_out)
    )
    else None in

  (* Now construct the virt-install command. *)
  let vi = make_virt_install_command os arch ks tmpname tmpout tmpefivars
                                     boot_media virtual_size_gb in

  (* Print the virt-install command just before we run it, because
   * this is expected to be long-running.
   *)
  print_virt_install_command stdout vi;

  (* Save the virt-install command to a file, for documentation. *)
  let chan = open_out (filename_of_os os arch ".virt-install-cmd") in
  fprintf chan "# This is the virt-install command which was used to create\n";
  fprintf chan "# the virt-builder template '%s'\n" (string_of_os os arch);
  fprintf chan "# NB: This file is generated for documentation purposes ONLY!\n";
  fprintf chan "# This script was never run, and is not intended to be run.\n";
  fprintf chan "\n";
  print_virt_install_command chan vi;
  close_out chan;

  (* Print the virt-install notes for OSes which cannot be automated
   * fully.  (These are different from the ‘notes=’ section in the
   * index fragment).
   *)
  print_install_notes os;
  printf "\n\n%!";

  (* Run the virt-install command. *)
  let pid = Unix.fork () in
  if pid = 0 then Unix.execvp "virt-install" vi;
  let _, pstat = Unix.waitpid [] pid in
  check_process_status_for_errors pstat;
  (* If there were NVRAM variables, move them to the final name and
   * compress them.  Doing this operation later means the cleanup of
   * the guest will remove them as well (because of --nvram).
   *)
  let nvram =
    match tmpefivars with
    | Some (_, vars) ->
       let f = sprintf "%s-nvram" output in
       let cmd = sprintf "mv %s %s" (quote vars) (quote f) in
       if Sys.command cmd <> 0 then exit 1;
       let cmd = sprintf "xz -f --best %s" (quote f) in
       if Sys.command cmd <> 0 then exit 1;
       Some (f ^ ".xz")
    | None -> None in

  ignore (Sys.command "sync");

  (* Run virt-filesystems, simply to display the filesystems in the image. *)
  let cmd = sprintf "virt-filesystems -a %s --all --long -h" (quote tmpout) in
  if Sys.command cmd <> 0 then exit 1;

  (* Some guests are special flowers that need post-installation
   * filesystem changes.
   *)
  let postinstall = make_postinstall os arch in

  (* Get the root filesystem.  If the root filesystem is LVM then
   * get the partition containing it.
   *)
  let g = open_guest ~mount:(postinstall <> None) tmpout in
  let roots = g#inspect_get_roots () in
  let expandfs, lvexpandfs =
    let rootfs = g#canonical_device_name roots.(0) in
    if String.length rootfs >= 7 && String.sub rootfs 0 7 = "/dev/sd" then
      rootfs, None (* non-LVM case *)
    else (
      (* The LVM case, find the containing partition to expand. *)
      let pvs = Array.to_list (g#pvs ()) in
      match pvs with
      | [pv] ->
         let pv = g#canonical_device_name pv in
         assert (String.length pv >= 7 && String.sub pv 0 7 = "/dev/sd");
         pv, Some rootfs
      | [] | _::_::_ -> assert false
    ) in

  (match postinstall with
   | None -> ()
   | Some f -> f g
  );

  g#shutdown ();
  g#close ();

  (match os with
   | Ubuntu (ver, _) when ver >= "14.04" ->
      (* In Ubuntu >= 14.04 you can't complete the install without creating
       * a user account.  We create one called 'builder', but we also
       * disable it.  XXX Combine with virt-sysprep step.
       *)
      let cmd =
        sprintf "virt-customize -a %s --password builder:disabled"
                (quote tmpout) in
      if Sys.command cmd <> 0 then exit 1
   | _ -> ()
  );

  if can_sysprep_os os then (
    (* Sysprep.  Relabel SELinux-using guests. *)
    printf "Sysprepping ...\n%!";
    let cmd =
      sprintf "virt-sysprep --quiet -a %s%s"
              (quote tmpout)
              (if is_selinux_os os then " --selinux-relabel" else "") in
    if Sys.command cmd <> 0 then exit 1
  );

  (* Sparsify and copy to output name. *)
  printf "Sparsifying ...\n%!";
  let cmd =
    sprintf "virt-sparsify --inplace --quiet %s" (quote tmpout) in
  if Sys.command cmd <> 0 then exit 1;

  (* Move file to final name before compressing. *)
  let cmd =
    sprintf "mv %s %s" (quote tmpout) (quote output) in
  if Sys.command cmd <> 0 then exit 1;

  (* Compress the output. *)
  printf "Compressing ...\n%!";
  let cmd =
    sprintf "xz -f --best --block-size=16777216 %s" (quote output) in
  if Sys.command cmd <> 0 then exit 1;
  let output = output ^ ".xz" in

  (* Set public readable permissions on the final file. *)
  let cmd = sprintf "chmod 0644 %s" (quote output) in
  if Sys.command cmd <> 0 then exit 1;

  printf "Template completed: %s\n%!" output;

  (* Construct the index fragment, but don't create this for the private
   * RHEL images.
   *)
  (match os with
   | RHEL _ -> ()
   | _ ->
      let index_fragment = filename_of_os os arch ".index-fragment" in
      (* If there is an existing file, read the revision and increment it. *)
      let revision = read_revision index_fragment in
      let revision =
        match revision with
        (* no existing file *)
        | `No_file -> None
        (* file exists, but no revision line, so revision=1 *)
        | `No_revision -> Some 2
        (* existing file with revision line *)
        | `Revision i -> Some (i+1) in
      make_index_fragment os arch index_fragment output nvram revision
                          expandfs lvexpandfs virtual_size_gb;

      (* Validate the fragment we have just created. *)
      let cmd = sprintf "virt-index-validate %s" (quote index_fragment) in
      if Sys.command cmd <> 0 then exit 1;
      printf "Index fragment created: %s\n" index_fragment
  );

  printf "Finished successfully.\n%!"

and parse_cmdline () =
  let anon = ref [] in

  let usage = "\
../../run ./make-template.ml [--options] os version [arch]

Usage:
  ../../run ./make-template.ml [--options] os version [arch]

Examples:
  ../../run ./make-template.ml fedora 25
  ../../run ./make-template.ml rhel 7.3 ppc64le

The arch defaults to x86_64.  Note that i686 is treated as a
separate arch.

Options:
" in
  let spec = Arg.align [
  ] in

  Arg.parse spec (fun s -> anon := s :: !anon) usage;

  let os, ver, arch =
    match List.rev !anon with
    | [os; ver] -> os, ver, "x86_64"
    | [os; ver; arch] -> os, ver, arch
    | _ ->
       eprintf "%s [--options] os version [arch]\n" prog;
       exit 1 in
  let os = os_of_string os ver
  and arch = arch_of_string arch in

  os, arch

and os_of_string os ver =
  match os, ver with
  | "alma", ver -> let maj, min = parse_major_minor ver in Alma (maj, min)
  | "centos", ver -> let maj, min = parse_major_minor ver in CentOS (maj, min)
  | "centosstream", ver -> CentOSStream(int_of_string ver)
  | "rhel", ver -> let maj, min = parse_major_minor ver in RHEL (maj, min)
  | "debian", "6" -> Debian (6, "squeeze")
  | "debian", "7" -> Debian (7, "wheezy")
  | "debian", "8" -> Debian (8, "jessie")
  | "debian", "9" -> Debian (9, "stretch")
  | "debian", "10" -> Debian (10, "buster")
  | "debian", "11" -> Debian (11, "bullseye")
  | "ubuntu", "10.04" -> Ubuntu (ver, "lucid")
  | "ubuntu", "12.04" -> Ubuntu (ver, "precise")
  | "ubuntu", "14.04" -> Ubuntu (ver, "trusty")
  | "ubuntu", "16.04" -> Ubuntu (ver, "xenial")
  | "ubuntu", "18.04" -> Ubuntu (ver, "bionic")
  | "ubuntu", "20.04" -> Ubuntu (ver, "focal")
  | "fedora", ver -> Fedora (int_of_string ver)
  | "freebsd", ver -> let maj, min = parse_major_minor ver in FreeBSD (maj, min)
  | "windows", ver -> parse_windows_version ver
  | _ ->
     eprintf "%s: unknown or unsupported OS (%s, %s)\n" prog os ver; exit 1

and parse_major_minor ver =
  let rex = Str.regexp "^\\([0-9]+\\)\\.\\([0-9]+\\)$" in
  if Str.string_match rex ver 0 then (
    int_of_string (Str.matched_group 1 ver),
    int_of_string (Str.matched_group 2 ver)
  )
  else (
    eprintf "%s: cannot parse major.minor (%s)\n" prog ver;
    exit 1
  )

(* https://en.wikipedia.org/wiki/List_of_Microsoft_Windows_versions *)
and parse_windows_version = function
  | "7" -> Windows (6, 1, Client)
  | "2k8r2" -> Windows (6, 1, Server)
  | "2k12" -> Windows (6, 2, Server)
  | "2k12r2" -> Windows (6, 3, Server)
  | "2k16" -> Windows (10, 0, Server)
  | _ ->
     eprintf "%s: cannot parse Windows version, see ‘parse_windows_version’\n"
             prog;
     exit 1

and arch_of_string = function
  | "x86_64" -> X86_64
  | "aarch64" -> Aarch64
  | "armv7l" -> Armv7
  | "i686" -> I686
  | "ppc64" -> PPC64
  | "ppc64le" -> PPC64le
  | "s390x" -> S390X
  | s ->
     eprintf "%s: unknown or unsupported arch (%s)\n" prog s; exit 1

and string_of_arch = function
  | X86_64 -> "x86_64"
  | Aarch64 -> "aarch64"
  | Armv7 -> "armv7l"
  | I686 -> "i686"
  | PPC64 -> "ppc64"
  | PPC64le -> "ppc64le"
  | S390X -> "s390x"

and debian_arch_of_arch = function
  | X86_64 -> "amd64"
  | Aarch64 -> "arm64"
  | Armv7 -> "armhf"
  | I686 -> "i386"
  | PPC64 -> "ppc64"
  | PPC64le -> "ppc64el"
  | S390X -> "s390x"

and filename_of_os os arch ext =
  match os with
  | Fedora ver ->
     if arch = X86_64 then sprintf "fedora-%d%s" ver ext
     else sprintf "fedora-%d-%s%s" ver (string_of_arch arch) ext
  | Alma (major, minor) ->
     if arch = X86_64 then sprintf "alma-%d.%d%s" major minor ext
     else sprintf "alma-%d.%d-%s%s" major minor (string_of_arch arch) ext
  | CentOS (major, minor) ->
     if arch = X86_64 then sprintf "centos-%d.%d%s" major minor ext
     else sprintf "centos-%d.%d-%s%s" major minor (string_of_arch arch) ext
  | CentOSStream ver ->
     if arch = X86_64 then sprintf "centosstream-%d%s" ver ext
     else sprintf "centosstream-%d-%s%s" ver (string_of_arch arch) ext
  | RHEL (major, minor) ->
     if arch = X86_64 then sprintf "rhel-%d.%d%s" major minor ext
     else sprintf "rhel-%d.%d-%s%s" major minor (string_of_arch arch) ext
  | Debian (ver, _) ->
     if arch = X86_64 then sprintf "debian-%d%s" ver ext
     else sprintf "debian-%d-%s%s" ver (string_of_arch arch) ext
  | Ubuntu (ver, _) ->
     if arch = X86_64 then sprintf "ubuntu-%s%s" ver ext
     else sprintf "ubuntu-%s-%s%s" ver (string_of_arch arch) ext
  | FreeBSD (major, minor) ->
     if arch = X86_64 then sprintf "freebsd-%d.%d%s" major minor ext
     else sprintf "freebsd-%d.%d-%s%s" major minor (string_of_arch arch) ext
  | Windows (major, minor, Client) ->
     if arch = X86_64 then sprintf "windows-%d.%d-client%s" major minor ext
     else sprintf "windows-%d.%d-client-%s%s"
                  major minor (string_of_arch arch) ext
  | Windows (major, minor, Server) ->
     if arch = X86_64 then sprintf "windows-%d.%d-server%s" major minor ext
     else sprintf "windows-%d.%d-server-%s%s"
                  major minor (string_of_arch arch) ext

and string_of_os os arch = filename_of_os os arch ""

(* This is what virt-builder called "os-version". *)
and string_of_os_noarch = function
  | Fedora ver -> sprintf "fedora-%d" ver
  | Alma (major, minor) -> sprintf "alma-%d.%d" major minor
  | CentOS (major, minor) -> sprintf "centos-%d.%d" major minor
  | CentOSStream ver -> sprintf "centosstream-%d" ver
  | RHEL (major, minor) -> sprintf "rhel-%d.%d" major minor
  | Debian (ver, _) -> sprintf "debian-%d" ver
  | Ubuntu (ver, _) -> sprintf "ubuntu-%s" ver
  | FreeBSD (major, minor) -> sprintf "freebsd-%d.%d" major minor
  | Windows (major, minor, Client) -> sprintf "windows-%d.%d-client" major minor
  | Windows (major, minor, Server) -> sprintf "windows-%d.%d-server" major minor

(* Does virt-sysprep know how to sysprep this OS? *)
and can_sysprep_os = function
  | RHEL _ | Alma _ | CentOS _ | CentOSStream _ | Fedora _
  | Debian _ | Ubuntu _ -> true
  | FreeBSD _ | Windows _ -> false

and is_selinux_os = function
  | RHEL _ | Alma _ | CentOS _ | CentOSStream _ | Fedora _ -> true
  | Debian _ | Ubuntu _
  | FreeBSD _ | Windows _ -> false

and needs_uefi os arch =
  match os, arch with
  | Fedora _, Armv7
  | Fedora _, Aarch64
  | RHEL _, Aarch64 -> true
  | RHEL _, _ | Alma _, _ | CentOS _, _ | CentOSStream _, _ | Fedora _, _
  | Debian _, _ | Ubuntu _, _
  | FreeBSD _, _ | Windows _, _ -> false

and get_virtual_size_gb os arch =
  match os with
  | RHEL _ | Alma _ | CentOS _ | CentOSStream _ | Fedora _
  | Debian _ | Ubuntu _
  | FreeBSD _ -> 6
  | Windows (10, _, _) -> 40    (* Windows 10 *)
  | Windows (6, _, _) -> 10     (* Windows from 2008 - 2012 *)
  | Windows (5, _, _) -> 6      (* Windows <= 2003 *)
  | Windows _ -> assert false

and make_kickstart os arch =
  match os with
  (* Kickstart. *)
  | Fedora _ | Alma _ | CentOS _ | CentOSStream _ | RHEL _ ->
     let ks_filename = filename_of_os os arch ".ks" in
     Some (make_kickstart_common ks_filename os arch)

  (* Preseed. *)
  | Debian _ -> Some (copy_preseed_to_temporary "debian.preseed")
  | Ubuntu _ -> Some (copy_preseed_to_temporary "ubuntu.preseed")

  (* Not automated. *)
  | FreeBSD _ -> None

  (* Windows unattend.xml wrapped in an ISO. *)
  | Windows _ -> Some (make_unattend_iso os arch)

and make_kickstart_common ks_filename os arch =
  let buf = Buffer.create 4096 in
  let bpf fs = bprintf buf fs in

  bpf "\
# Kickstart file for %s
# Generated by libguestfs.git/builder/templates/make-template.ml

" (string_of_os os arch);

  (* Fedora 34+ removes the "install" keyword. *)
  (match os with
   | Fedora n when n >= 34 -> ()
   | RHEL (n, _)
   | Alma (n, _) | CentOS (n, _) | CentOSStream n when n >= 9 -> ()
   | _ -> bpf "install\n";
  );

  bpf "\
text
reboot
lang en_US.UTF-8
keyboard us
network --bootproto dhcp
rootpw builder
firewall --enabled --ssh
timezone --utc America/New_York
";

  (match os with
   | RHEL (ver, _) when ver <= 4 ->
      bpf "\
langsupport en_US
mouse generic
";
   | _ -> ()
  );

  (match os with
   | RHEL (3, _) -> ()
   | _ ->
      bpf "selinux --enforcing\n"
  );

  (match os with
   | RHEL (5, _) -> bpf "key --skip\n"
   | _ -> ()
  );
  bpf "\n";

  bpf "bootloader --location=mbr --append=\"%s\"\n"
      (kernel_cmdline_of_os os arch);
  bpf "\n";

  (* Required as a workaround for CentOS 8.0, see:
   * https://lists.centos.org/pipermail/centos-devel/2019-September/017813.html
   * https://lists.centos.org/pipermail/centos-devel/2019-October/017882.html
   *)
  (match os with
   | CentOS (8, _) ->
      bpf "url --url=\"https://vault.centos.org/8.5.2111/BaseOS/x86_64/os/\"\n"
   | _ -> ()
  );
  bpf "\n";

  (match os with
   | CentOS ((3|4|5|6) as major, _) | RHEL ((3|4|5|6) as major, _) ->
      let bootfs = if major <= 5 then "ext2" else "ext4" in
      let rootfs = if major <= 4 then "ext3" else "ext4" in
      bpf "\
zerombr
clearpart --all --initlabel
part /boot --fstype=%s   --size=512         --asprimary
part swap                --size=1024        --asprimary
part /     --fstype=%s   --size=1024 --grow --asprimary
" bootfs rootfs;
   | Alma _ | CentOS _ | CentOSStream _ | RHEL _ | Fedora _ ->
      bpf "\
zerombr
clearpart --all --initlabel --disklabel=gpt
autopart --type=plain
";
   | _ -> assert false (* cannot happen, see caller *)
  );
  bpf "\n";

  (match os with
   | RHEL (3, _) -> ()
   | _ ->
      bpf "\
# Halt the system once configuration has finished.
poweroff
";
  );
  bpf "\n";

  bpf "\
%%packages
@core
";

  (match os with
   | RHEL ((3|4|5), _) -> ()
   | _ ->
      bpf "%%end\n"
  );
  bpf "\n";

  (* Generate the %post script section.  The previous scripts did
   * many different things here.  The current script tries to update
   * the packages and enable Xen drivers only.
   *)
  let regenerate_dracut () =
    bpf "\
# To make dracut config changes permanent, we need to rerun dracut.
# Rerun dracut for the installed kernel (not the running kernel).
# See commit 0fa52e4e45d80874bc5ea5f112f74be1d3f3472f and
# https://www.redhat.com/archives/libguestfs/2014-June/thread.html#00045
KERNEL_VERSION=\"$(rpm -q kernel --qf '%%{version}-%%{release}.%%{arch}\\n' | sort -V | tail -1)\"
dracut -f /boot/initramfs-$KERNEL_VERSION.img $KERNEL_VERSION
"
  in

  (match os with
   | Fedora _ ->
      bpf "%%post\n";
      bpf "\
# Ensure the installation is up-to-date.
# This makes Fedora >= 33 unbootable, see:
# https://bugzilla.redhat.com/show_bug.cgi?id=1911177
#dnf -y --best upgrade
";

      let needs_regenerate_dracut = ref false in
      if arch = X86_64 then (
        bpf "\
# Enable Xen domU support.
pushd /etc/dracut.conf.d
echo 'add_drivers+=\" xen:vbd xen:vif \"' > virt-builder-xen-drivers.conf
popd
";
        needs_regenerate_dracut := true
      );

      if arch = PPC64 || arch = PPC64le then (
        bpf "\
# Enable virtio-scsi support.
pushd /etc/dracut.conf.d
echo 'add_drivers+=\" virtio-blk virtio-scsi \"' > virt-builder-virtio-scsi.conf
popd
";
        needs_regenerate_dracut := true
      );

      if !needs_regenerate_dracut then regenerate_dracut ();
      bpf "%%end\n\n"

   | RHEL (7,_) ->
      bpf "%%post\n";

      let needs_regenerate_dracut = ref false in

      if arch = PPC64 || arch = PPC64le then (
        bpf "\
# Enable virtio-scsi support.
pushd /etc/dracut.conf.d
echo 'add_drivers+=\" virtio-blk virtio-scsi \"' > virt-builder-virtio-scsi.conf
popd
";
        needs_regenerate_dracut := true
      );

      if !needs_regenerate_dracut then regenerate_dracut ();
      bpf "%%end\n\n"

   | _ -> ()
  );

  bpf "# EOF\n";

  (* Write out the kickstart file. *)
  let chan = open_out (ks_filename ^ ".new") in
  Buffer.output_buffer chan buf;
  close_out chan;
  let cmd =
    sprintf "mv %s %s" (quote (ks_filename ^ ".new")) (quote ks_filename) in
  if Sys.command cmd <> 0 then exit 1;

  (* Return the kickstart filename. *)
  ks_filename

and copy_preseed_to_temporary source =
  (* d-i only works if the file is literally called "/preseed.cfg" *)
  let d = Filename.get_temp_dir_name () // random8 () ^ ".tmp" in
  let f = d // "preseed.cfg" in
  Unix.mkdir d 0o700;
  let cmd = sprintf "cp %s %s" (quote source) (quote f) in
  if Sys.command cmd <> 0 then exit 1;
  f

(* For Windows:
 * https://serverfault.com/questions/644437/unattended-installation-of-windows-server-2012-on-kvm
 *)
and make_unattend_iso os arch =
  printf "enter Windows product key: ";
  let product_key = read_line () in

  let output_iso =
    Sys.getcwd () // filename_of_os os arch "-unattend.iso" in
  unlink_on_exit output_iso;

  let d = Filename.get_temp_dir_name () // random8 () in
  Unix.mkdir d 0o700;
  let config_dir = d // "config" in
  Unix.mkdir config_dir 0o700;
  let f = config_dir // "autounattend.xml" in

  let chan = open_out f in
  let arch =
    match arch with
    | X86_64 -> "amd64"
    | I686 -> "x86"
    | _ ->
       eprintf "%s: Windows architecture %s not supported\n"
               prog (string_of_arch arch);
       exit 1 in
  (* Tip: If the install fails with a useless error "The answer file is
   * invalid", type Shift + F10 into the setup screen and look for a
   * file called \Windows\Panther\Setupact.log (NB:
   * not \Windows\Setupact.log)
   *)
  fprintf chan "
<unattend xmlns=\"urn:schemas-microsoft-com:unattend\"
          xmlns:ms=\"urn:schemas-microsoft-com:asm.v3\"
          xmlns:wcm=\"http://schemas.microsoft.com/WMIConfig/2002/State\">
  <settings pass=\"windowsPE\">
    <component name=\"Microsoft-Windows-Setup\"
               publicKeyToken=\"31bf3856ad364e35\"
               language=\"neutral\"
               versionScope=\"nonSxS\"
               processorArchitecture=\"%s\">
      <UserData>
        <AcceptEula>true</AcceptEula>
        <ProductKey>
          <Key>%s</Key>
          <WillShowUI>OnError</WillShowUI>
        </ProductKey>
      </UserData>

      <DiskConfiguration>
        <Disk wcm:action=\"add\">
          <DiskID>0</DiskID>
          <WillWipeDisk>true</WillWipeDisk>
          <CreatePartitions>
            <!-- System partition -->
            <CreatePartition wcm:action=\"add\">
              <Order>1</Order>
              <Type>Primary</Type>
              <Size>300</Size>
            </CreatePartition>
            <!-- Windows partition -->
            <CreatePartition wcm:action=\"add\">
              <Order>2</Order>
              <Type>Primary</Type>
              <Extend>true</Extend>
            </CreatePartition>
          </CreatePartitions>
          <ModifyPartitions>
            <!-- System partition -->
            <ModifyPartition wcm:action=\"add\">
              <Order>1</Order>
              <PartitionID>1</PartitionID>
              <Label>System</Label>
              <Format>NTFS</Format>
              <Active>true</Active>
            </ModifyPartition>
            <!-- Windows partition -->
            <ModifyPartition wcm:action=\"add\">
              <Order>2</Order>
              <PartitionID>2</PartitionID>
              <Label>Windows</Label>
              <Letter>C</Letter>
              <Format>NTFS</Format>
            </ModifyPartition>
          </ModifyPartitions>
        </Disk>
        <WillShowUI>OnError</WillShowUI>
      </DiskConfiguration>

      <ImageInstall>
        <OSImage>
          <WillShowUI>Never</WillShowUI>
          <InstallFrom>
            <MetaData>
              <Key>/IMAGE/INDEX</Key>
              <Value>1</Value>
            </MetaData>
          </InstallFrom>
          <InstallTo>
            <DiskID>0</DiskID>
            <PartitionID>2</PartitionID>
          </InstallTo>
        </OSImage>
      </ImageInstall>
    </component>

    <component name=\"Microsoft-Windows-International-Core-WinPE\"
               publicKeyToken=\"31bf3856ad364e35\"
               language=\"neutral\"
               versionScope=\"nonSxS\"
               processorArchitecture=\"%s\">
      <SetupUILanguage>
        <UILanguage>en-US</UILanguage>
      </SetupUILanguage>
      <SystemLocale>en-US</SystemLocale>
      <UILanguage>en-US</UILanguage>
      <UserLocale>en-US</UserLocale>
    </component>
  </settings>
</unattend>"
          arch product_key arch;
  close_out chan;

  let cmd = sprintf "cd %s && mkisofs -o %s -J -r config"
                    (quote d) (quote output_iso) in
  if Sys.command cmd <> 0 then exit 1;
  let cmd = sprintf "rm -rf %s" (quote d) in
  if Sys.command cmd <> 0 then exit 1;

  (* Return the name of the unattend ISO. *)
  output_iso

and make_boot_media os arch =
  match os, arch with
  | Alma (major, minor), X86_64 ->
     (* UK mirror *)
     Location (sprintf "http://mirror.cov.ukservers.com/almalinux/%d.%d/BaseOS/x86_64/kickstart/"
                 major minor)

  | CentOS (major, _), Aarch64 ->
     (* XXX This always points to the latest CentOS, so
      * effectively the minor number is always ignored.
      *)
     Location (sprintf "http://mirror.centos.org/altarch/%d/os/aarch64/"
                       major)

  | CentOS (7, _), X86_64 ->
     (* For 6.x we rebuild this every time there is a new 6.x release, and bump
      * the revision in the index.
      * For 7.x this always points to the latest CentOS, so
      * effectively the minor number is always ignored.
      *)
     Location "http://mirror.centos.org/centos-7/7/os/x86_64/"

  | CentOS (8, _), X86_64 ->
     (* This is probably the last CentOS 8 release. *)
     Location "https://vault.centos.org/8.5.2111/BaseOS/x86_64/kickstart/"

  | CentOSStream 8, X86_64 ->
     Location (sprintf "http://mirror.centos.org/centos/8-stream/BaseOS/x86_64/os")

  | CentOSStream ver, X86_64 ->
     Location (sprintf "http://mirror.stream.centos.org/%d-stream/BaseOS/x86_64/os" ver)

  | Debian (_, dist), arch ->
     Location (sprintf "http://deb.debian.org/debian/dists/%s/main/installer-%s"
                       dist (debian_arch_of_arch arch))

  (* Fedora primary architectures. *)
  | Fedora ver, Armv7 ->
     Location (sprintf "https://mirror.bytemark.co.uk/fedora/linux/releases/%d/Server/armhfp/os/" ver)

  | Fedora ver, X86_64 when ver < 21 ->
     Location (sprintf "https://mirror.bytemark.co.uk/fedora/linux/releases/%d/Fedora/x86_64/os/" ver)

  | Fedora ver, X86_64 ->
     Location (sprintf "https://mirror.bytemark.co.uk/fedora/linux/releases/%d/Server/x86_64/os/" ver)

  | Fedora ver, Aarch64 ->
     Location (sprintf "https://mirror.bytemark.co.uk/fedora/linux/releases/%d/Server/aarch64/os/" ver)

  (* Fedora secondary architectures.
   * By using dl.fedoraproject.org we avoid randomly using mirrors
   * which might have incomplete copies.
   *)
  | Fedora ver, I686 ->
     Location (sprintf "https://dl.fedoraproject.org/pub/fedora-secondary/releases/%d/Server/i386/os/" ver)

  | Fedora ver, PPC64 ->
     Location (sprintf "https://dl.fedoraproject.org/pub/fedora-secondary/releases/%d/Server/ppc64/os/" ver)

  | Fedora ver, PPC64le ->
     Location (sprintf "https://dl.fedoraproject.org/pub/fedora-secondary/releases/%d/Server/ppc64le/os/" ver)

  | Fedora ver, S390X ->
     Location (sprintf "https://dl.fedoraproject.org/pub/fedora-secondary/releases/%d/Server/s390x/os/" ver)

  | RHEL (3, minor), X86_64 ->
     Location (sprintf "http://download.devel.redhat.com/released/RHEL-3/U%d/AS/x86_64/tree" minor)

  | RHEL (4, minor), X86_64 ->
     Location (sprintf "http://download.devel.redhat.com/released/RHEL-4/U%d/AS/x86_64/tree" minor)

  | RHEL (5, minor), I686 ->
     Location (sprintf "http://download.devel.redhat.com/released/RHEL-5-Server/U%d/i386/os" minor)

  | RHEL (5, minor), X86_64 ->
     Location (sprintf "http://download.devel.redhat.com/released/RHEL-5-Server/U%d/x86_64/os" minor)

  | RHEL (6, minor), I686 ->
     Location (sprintf "http://download.devel.redhat.com/released/RHEL-6/6.%d/Server/i386/os" minor)

  | RHEL (6, minor), X86_64 ->
     Location (sprintf "http://download.devel.redhat.com/released/RHEL-6/6.%d/Server/x86_64/os" minor)

  | RHEL (7, minor), X86_64 ->
     Location (sprintf "http://download.devel.redhat.com/released/rhel-6-7-8/rhel-7/RHEL-7/7.%d/Server/x86_64/os" minor)

  | RHEL (7, minor), PPC64 ->
     Location (sprintf "http://download.devel.redhat.com/released/rhel-6-7-8/rhel-7/RHEL-7/7.%d/Server/ppc64/os" minor)

  | RHEL (7, minor), PPC64le ->
     Location (sprintf "http://download.devel.redhat.com/released/rhel-6-7-8/rhel-7/RHEL-7/7.%d/Server/ppc64le/os" minor)

  | RHEL (7, minor), S390X ->
     Location (sprintf "http://download.devel.redhat.com/released/rhel-6-7-8/rhel-7/RHEL-7/7.%d/Server/s390x/os" minor)

  | RHEL (7, minor), Aarch64 ->
     Location (sprintf "http://download.eng.bos.redhat.com/released/RHEL-ALT-7/7.%d/Server/aarch64/os" minor)

  | RHEL (8, minor), arch ->
     Location (sprintf "http://download.eng.bos.redhat.com/released/rhel-6-7-8/rhel-8/RHEL-8/8.%d.0/BaseOS/%s/os" minor (string_of_arch arch))

  | Ubuntu (_, dist), X86_64 ->
     Location (sprintf "http://archive.ubuntu.com/ubuntu/dists/%s/main/installer-amd64" dist)

  | Ubuntu (_, dist), PPC64le ->
     Location (sprintf "http://ports.ubuntu.com/ubuntu-ports/dists/%s/main/installer-ppc64el" dist)

  | FreeBSD (major, minor), X86_64 ->
     let iso = sprintf "FreeBSD-%d.%d-RELEASE-amd64-disc1.iso"
                       major minor in
     let iso_xz = sprintf "ftp://ftp.freebsd.org/pub/FreeBSD/releases/amd64/amd64/ISO-IMAGES/%d.%d/%s.xz"
                       major minor iso in
     let cmd = sprintf "wget -nc %s" (quote iso_xz) in
     if Sys.command cmd <> 0 then exit 1;
     let cmd = sprintf "unxz -f --keep %s.xz" iso in
     if Sys.command cmd <> 0 then exit 1;
     CDRom iso

  | Windows (major, minor, variant), arch ->
     let iso_name =
       match major, minor, variant, arch with
       | 6, 1, Client, X86_64 -> (* Windows 7 *)
          "en_windows_7_ultimate_with_sp1_x64_dvd_u_677332.iso"
       | 6, 1, Server, X86_64 -> (* Windows 2008 R2 *)
          "en_windows_server_2008_r2_with_sp1_x64_dvd_617601.iso"
       | 6, 2, Server, X86_64 -> (* Windows Server 2012 *)
          "en_windows_server_2012_x64_dvd_915478.iso"
       | 6, 3, Server, X86_64 -> (* Windows Server 2012 R2 *)
          "en_windows_server_2012_r2_with_update_x64_dvd_6052708.iso"
       | 10, 0, Server, X86_64 -> (* Windows Server 2016 *)
          "en_windows_server_2016_updated_feb_2018_x64_dvd_11636692.iso"
       | _ ->
          eprintf "%s: don't have an installer ISO for this version of Windows\n"
                  prog;
          exit 1 in
     CDRom (windows_installers // iso_name)

  | _ ->
     eprintf "%s: don't know how to calculate the --location for this OS and architecture\n" prog;
     exit 1

and print_install_notes = function
  | Ubuntu _ ->
     printf "\
Some preseed functions are not automated.  You may need to hit [Return]
a few times during the install.\n"

  | FreeBSD _ ->
     printf "\
The FreeBSD install is not automated.  Select all defaults, except:

 - root password:  builder
 - timezone:       UTC
 - do not add any user accounts\n"

  | _ -> ()

(* If the install is not automated and we need a graphical console. *)
and needs_graphics = function
  | Alma _ | CentOS _ | CentOSStream _ | RHEL _
  | Debian _ | Ubuntu _ | Fedora _ -> false
  | FreeBSD _ | Windows _ -> true

(* NB: Arguments do not need to be quoted, because we pass them
 * directly to exec(2).
 *)
and make_virt_install_command os arch ks tmpname tmpout tmpefivars
                              boot_media virtual_size_gb =
  let args = ref [] in
  let add arg = args := arg :: !args in

  add "virt-install";

  (* This ensures the libvirt domain will be automatically deleted
   * when virt-install exits.  However it doesn't work for certain
   * types of guest.
   *)
  (match os with
   | Windows _ ->
      printf "after Windows has installed, do:\n";
      printf "  virsh shutdown %s\n  virsh undefine %s\n%!" tmpname tmpname;
   | _ -> add "--transient"
  );

  (* Don't try relabelling everything.  This is particularly necessary
   * for the Windows install ISOs which are located on NFS.
   *)
  (match os with
   | Windows _ -> add "--security=type=none"
   | _ -> ()
  );

  add (sprintf "--name=%s" tmpname);

  (*add "--print-xml";*)

  add "--ram=4096";

  (match arch with
   | X86_64 ->
      add "--arch=x86_64";
      add "--cpu=host";
      add "--vcpus=4"
   | PPC64 ->
      add "--arch=ppc64";
      add "--machine=pseries";
      add "--cpu=power7";
      add "--vcpus=1"
   | PPC64le ->
      add "--arch=ppc64le";
      add "--machine=pseries";
      add "--cpu=power8";
      add "--vcpus=1"
   | Armv7 ->
      add "--arch=armv7l";
      add "--machine=virt-2.11"; (* RHBZ#1633328, RHBZ#2003706 *)
      add "--vcpus=1"
   | arch ->
      add (sprintf "--arch=%s" (string_of_arch arch));
      add "--vcpus=1"
  );

  add (sprintf "--os-variant=%s" (os_variant_of_os ~for_fedora:true os arch));

  (match tmpefivars with
   | Some (code, vars) ->
      add "--boot";
      add (sprintf "loader=%s,loader_ro=yes,loader_type=pflash,nvram=%s"
                   code vars)
   | _ -> ()
  );

  (* --initrd-inject and --extra-args flags for Linux only. *)
  (match os with
   | Debian _ | Ubuntu _
   | Fedora _ | RHEL _ | Alma _ | CentOS _ | CentOSStream _ ->
      let ks =
        match ks with None -> assert false | Some ks -> ks in
      add (sprintf "--initrd-inject=%s" ks);

      let os_extra =
        match os with
        | Debian _ | Ubuntu _ -> "auto"
        | Fedora n when n >= 34 ->
           sprintf "inst.ks=file:/%s" (Filename.basename ks)
        | Alma (major, _) ->
           (* This is only required because of missing osinfo-db data.
            * https://bugs.almalinux.org/view.php?id=127
            * Once this is fixed, do the same as CentOS below.
            *)
           sprintf "inst.ks=file:/%s inst.repo=http://repo.almalinux.org/almalinux/%d/BaseOS/x86_64/os/" (Filename.basename ks) major
        | RHEL (n, _) | CentOS (n, _) | CentOSStream n when n >= 9 ->
           sprintf "inst.ks=file:/%s" (Filename.basename ks)
        | Fedora _ | RHEL _ | CentOS _ | CentOSStream _ ->
           sprintf "ks=file:/%s" (Filename.basename ks)
        | FreeBSD _ | Windows _ -> assert false in
      let proxy =
        let p = try Some (Sys.getenv "http_proxy") with Not_found -> None in
        match p with
        | None ->
           (match os with
            | Fedora _ | RHEL _ | Alma _ | CentOS _ | CentOSStream _
            | Ubuntu _ -> ""
            | Debian _ -> "mirror/http/proxy="
            | FreeBSD _ | Windows _ -> assert false
           )
        | Some p ->
           match os with
           | Fedora n when n >= 34 -> sprintf "inst.proxy=" ^ p
           | RHEL (n, _)
           | Alma (n, _) | CentOS (n, _) | CentOSStream n when n >= 9 ->
              "inst.proxy=" ^ p
           | Fedora _ | RHEL _ | Alma _ | CentOS _ | CentOSStream _ ->
              "proxy=" ^ p
           | Debian _ | Ubuntu _ -> "mirror/http/proxy=" ^ p
           | FreeBSD _ | Windows _ -> assert false in

      add (sprintf "--extra-args=%s %s %s" (* sic: does NOT need to be quoted *)
                   os_extra proxy (kernel_cmdline_of_os os arch));

   (* doesn't need --initrd-inject *)
   | FreeBSD _ | Windows _ -> ()
  );

  add (sprintf "--disk=%s,size=%d,format=raw"
               (Sys.getcwd () // tmpout) virtual_size_gb);

  (match boot_media with
   | Location location -> add (sprintf "--location=%s" location)
   | CDRom iso -> add (sprintf "--disk=%s,device=cdrom,boot_order=1" iso)
  );

  (* Windows requires one or two extra CDs!
   * See: https://serverfault.com/questions/644437/unattended-installation-of-windows-server-2012-on-kvm
   *)
  (match os with
   | Windows _ ->
      let unattend_iso =
        match ks with None -> assert false | Some ks -> ks in
      (*add "--disk=/usr/share/virtio-win/virtio-win.iso,device=cdrom,boot_order=98";*)
      add (sprintf "--disk=%s,device=cdrom,boot_order=99" unattend_iso)
   | _ -> ()
  );

  add "--serial=pty";
  if not (needs_graphics os) then add "--nographics";

  (* Return the command line (list of arguments). *)
  Array.of_list (List.rev !args)

and print_virt_install_command chan vi =
  Array.iter (
    fun arg ->
      if arg.[0] = '-' then fprintf chan "\\\n    %s " (quote arg)
      else fprintf chan "%s " (quote arg)
  ) vi;
  fprintf chan "\n\n%!"

(* The optional [?for_fedora] flag means that we only return
 * libosinfo data as currently supported by the latest version of
 * Fedora.
 *
 * This is because if you try to use [virt-install --os-variant=...]
 * with an os-variant which the host doesn't support, it won't work,
 * and I currently use Fedora, so whatever is supported there matters.
 *)
and os_variant_of_os ?(for_fedora = false) os arch =
  if not for_fedora then (
    match os with
    | Fedora ver -> sprintf "fedora%d" ver
    | Alma (major, _) -> sprintf "almalinux%d" major
    | CentOS (major, minor) -> sprintf "centos%d.%d" major minor
    | CentOSStream ver -> sprintf "centosstream%d" ver
    | RHEL (major, minor) -> sprintf "rhel%d.%d" major minor
    | Debian (ver, _) -> sprintf "debian%d" ver
    | Ubuntu (ver, _) -> sprintf "ubuntu%s" ver
    | FreeBSD (major, minor) -> sprintf "freebsd%d.%d" major minor

    | Windows (6, 1, Client) -> "win7"
    | Windows (6, 1, Server) -> "win2k8r2"
    | Windows (6, 2, Server) -> "win2k12"
    | Windows (6, 3, Server) -> "win2k12r2"
    | Windows (10, 0, Server) -> "win2k16"
    | Windows _ -> assert false
  )
  else (
    match os, arch with
    (* This special case for Fedora/ppc64{,le} is needed to work
     * around a bug in virt-install:
     * https://bugzilla.redhat.com/show_bug.cgi?id=1399083
     *)
    | Fedora _, (PPC64|PPC64le) -> "fedora22"
    | Fedora ver, _ when ver <= 23 ->
       sprintf "fedora%d" ver
    | Fedora _, _ -> "fedora34" (* max version known in Fedora 34 *)

    | Alma (major, _), _ -> sprintf "almalinux%d" major

    | CentOS (8, _), _ -> "rhel8.0" (* temporary until osinfo updated *)
    | CentOS (major, minor), _ when (major, minor) <= (7,0) ->
       sprintf "centos%d.%d" major minor
    | CentOS _, _ -> "centos7.0" (* max version known in Fedora 31 *)

    | CentOSStream 8, _ -> "rhel8.0" (* temporary until osinfo updated *)
    | CentOSStream _, _ -> "rhel8.0" (* min known version is 8 *)

    | RHEL (6, minor), _ when minor <= 8 ->
       sprintf "rhel6.%d" minor
    | RHEL (6, _), _ -> "rhel6.9" (* max version known in Fedora 29 *)
    | RHEL (7, minor), _ when minor <= 4 ->
       sprintf "rhel7.%d" minor
    | RHEL (7, _), _ -> "rhel7.5" (* max version known in Fedora 29 *)
    | RHEL (8, _), _ -> "rhel8.0" (* temporary until osinfo updated *)
    | RHEL (major, minor), _ ->
       sprintf "rhel%d.%d" major minor

    | Debian (ver, _), _ when ver <= 8 -> sprintf "debian%d" ver
    | Debian _, _ -> "debian8" (* max version known in Fedora 26 *)

    | Ubuntu (ver, _), _ when ver < "20.04" -> sprintf "ubuntu%s" ver
    | Ubuntu ("20.04", _), _ -> "ubuntu19.10"
    | Ubuntu _, _ -> assert false

    | FreeBSD (major, minor), _ -> sprintf "freebsd%d.%d" major minor

    | Windows (6, 1, Client), _ -> "win7"
    | Windows (6, 1, Server), _ -> "win2k8r2"
    | Windows (6, 2, Server), _ -> "win2k12"
    | Windows (6, 3, Server), _ -> "win2k12r2"
    | Windows (10, 0, Server), _ -> "win2k16"
    | Windows _, _ -> assert false
  )

and kernel_cmdline_of_os os arch =
  match os, arch with
  | _, X86_64
  | _, I686
  | _, S390X ->
     "console=tty0 console=ttyS0,115200 rd_NO_PLYMOUTH"
  | _, Aarch64 ->
     "console=ttyAMA0 earlyprintk=pl011,0x9000000 ignore_loglevel no_timer_check printk.time=1 rd_NO_PLYMOUTH"
  | _, Armv7 ->
     "console=tty0 console=ttyAMA0,115200 rd_NO_PLYMOUTH"
  | (Debian _|Fedora _|Ubuntu _), (PPC64|PPC64le) ->
     "console=tty0 console=hvc0 rd_NO_PLYMOUTH"
  | (RHEL _ | Alma _ | CentOS _ | CentOSStream _), PPC64
  | (RHEL _ | Alma _ | CentOS _ | CentOSStream _), PPC64le ->
     "console=tty0 console=ttyS0,115200 rd_NO_PLYMOUTH"

  | FreeBSD _, _ | Windows _, _ -> assert false

and make_postinstall os arch =
  match os with
  | Debian _ | Ubuntu _ ->
     Some (
       fun g ->
         (* Remove apt proxy configuration (thanks: Daniel Miranda). *)
         g#rm_f "/etc/apt/apt.conf";
         g#touch "/etc/apt/apt.conf"
     )

  | RHEL (major, minor) when major >= 5 ->
     Some (
       fun g ->
         (* RHEL guests require alternate yum configuration pointing to
          * Red Hat's internal servers.
          *)
         let yum_conf = make_rhel_yum_conf major minor arch in
         g#write "/etc/yum.repos.d/download.devel.redhat.com.repo" yum_conf
     )

  | RHEL _ | Fedora _ | Alma _ | CentOS _ | CentOSStream _
  | FreeBSD _ | Windows _ -> None

and make_rhel_yum_conf major minor arch =
  let buf = Buffer.create 4096 in
  let bpf fs = bprintf buf fs in

  if major <= 8 then (
    let baseurl, srpms, optional =
      match major, arch with
      | 5, (I686|X86_64) ->
         let arch = match arch with I686 -> "i386" | _ -> string_of_arch arch in
         let topurl =
           sprintf "http://download.devel.redhat.com/released/RHEL-5-Server/U%d"
                   minor in
         sprintf "%s/%s/os/Server" topurl arch,
         sprintf "%s/source/SRPMS" topurl,
         None
      | 6, (I686|X86_64) ->
         let arch = match arch with I686 -> "i386" | _ -> string_of_arch arch in
         let topurl =
           sprintf "http://download.devel.redhat.com/released/RHEL-%d/%d.%d"
                   major major minor in
         sprintf "%s/Server/%s/os" topurl arch,
         sprintf "%s/source/SRPMS" topurl,
         Some ("Optional",
               sprintf "%s/Server/optional/%s/os" arch topurl,
               sprintf "%s/Server/optional/source/SRPMS" topurl)
      | 7, (X86_64|PPC64|PPC64le|S390X) ->
         let topurl =
           sprintf "http://download.devel.redhat.com/released/RHEL-%d/%d.%d"
                   major major minor in
         sprintf "%s/Server/%s/os" topurl (string_of_arch arch),
         sprintf "%s/Server/source/tree" topurl,
         Some ("Optional",
               sprintf "%s/Server-optional/%s/os" topurl (string_of_arch arch),
               sprintf "%s/Server-optional/source/tree" topurl)
      | 7, Aarch64 ->
         let topurl =
           sprintf "http://download.devel.redhat.com/released/RHEL-ALT-%d/%d.%d"
                   major major minor in
         sprintf "%s/Server/%s/os" topurl (string_of_arch arch),
         sprintf "%s/Server/source/tree" topurl,
         Some ("Optional",
               sprintf "%s/Server-optional/%s/os" topurl (string_of_arch arch),
               sprintf "%s/Server-optional/source/tree" topurl)
      | 8, arch ->
         let topurl =
           sprintf "http://download.devel.redhat.com/released/RHEL-%d/%d.%d.0"
                   major major minor in
         sprintf "%s/BaseOS/%s/os" topurl (string_of_arch arch),
         sprintf "%s/BaseOS/source/tree" topurl,
         Some ("AppStream",
               sprintf "%s/AppStream/%s/os" topurl (string_of_arch arch),
               sprintf "%s/AppStream/source/tree" topurl)
      | _ -> assert false in

    bpf "\
# Yum configuration pointing to Red Hat servers.

[rhel%d]
name=RHEL %d Server
baseurl=%s
enabled=1
gpgcheck=0
keepcache=0

[rhel%d-source]
name=RHEL %d Server Source
baseurl=%s
enabled=0
gpgcheck=0
keepcache=0
" major major baseurl major major srpms;

    (match optional with
     | None -> ()
     | Some (name, optionalbaseurl, optionalsrpms) ->
        let lc_name = String.lowercase_ascii name in
        bpf "\

[rhel%d-%s]
name=RHEL %d Server %s
baseurl=%s
enabled=1
gpgcheck=0
keepcache=0

[rhel%d-%s-source]
name=RHEL %d Server %s
baseurl=%s
enabled=0
gpgcheck=0
keepcache=0
" major lc_name major lc_name optionalbaseurl
  major lc_name major lc_name optionalsrpms
    )
  ) else (
    assert false (* not implemented for RHEL major >= 9 *)
  );

  Buffer.contents buf

and make_index_fragment os arch index_fragment output nvram revision
                        expandfs lvexpandfs virtual_size_gb =
  let virtual_size = Int64.of_int virtual_size_gb in
  let virtual_size = Int64.mul virtual_size 1024_L in
  let virtual_size = Int64.mul virtual_size 1024_L in
  let virtual_size = Int64.mul virtual_size 1024_L in

  let chan = open_out (index_fragment ^ ".new") in
  let fpf fs = fprintf chan fs in

  fpf "[%s]\n" (string_of_os_noarch os);
  fpf "name=%s\n" (long_name_of_os os arch);
  fpf "osinfo=%s\n" (os_variant_of_os os arch);
  fpf "arch=%s\n" (string_of_arch arch);
  fpf "file=%s\n" output;
  (match revision with
   | None -> ()
   | Some i -> fpf "revision=%d\n" i
  );
  fpf "checksum[sha512]=%s\n" (sha512sum_of_file output);
  fpf "format=raw\n";
  fpf "size=%Ld\n" virtual_size;
  fpf "compressed_size=%d\n" (size_of_file output);
  fpf "expand=%s\n" expandfs;
  (match lvexpandfs with
   | None -> ()
   | Some fs -> fpf "lvexpand=%s\n" fs
  );

  let notes = notes_of_os os arch nvram in
  (match notes with
   | first :: notes ->
      fpf "notes=%s\n" first;
      List.iter (fpf " %s\n") notes
   | [] -> assert false
  );
  fpf "\n";

  close_out chan;
  let cmd =
    sprintf "mv %s %s"
            (quote (index_fragment ^ ".new")) (quote index_fragment) in
  if Sys.command cmd <> 0 then exit 1

and long_name_of_os os arch =
  match os, arch with
  | Alma (major, minor), X86_64 ->
     sprintf "AlmaLinux %d.%d" major minor
  | Alma (major, minor), arch ->
     sprintf "AlmaLinux %d.%d (%s)" major minor (string_of_arch arch)
  | CentOS (major, minor), X86_64 ->
     sprintf "CentOS %d.%d" major minor
  | CentOS (major, minor), arch ->
     sprintf "CentOS %d.%d (%s)" major minor (string_of_arch arch)
  | CentOSStream ver, X86_64 ->
     sprintf "CentOS Stream %d" ver
  | CentOSStream ver, arch ->
     sprintf "CentOS Stream %d (%s)" ver (string_of_arch arch)
  | Debian (ver, dist), X86_64 ->
     sprintf "Debian %d (%s)" ver dist
  | Debian (ver, dist), arch ->
     sprintf "Debian %d (%s) (%s)" ver dist (string_of_arch arch)
  | Fedora ver, X86_64 ->
     sprintf "Fedora® %d Server" ver
  | Fedora ver, arch ->
     sprintf "Fedora® %d Server (%s)" ver (string_of_arch arch)
  | RHEL (major, minor), X86_64 ->
     sprintf "Red Hat Enterprise Linux® %d.%d" major minor
  | RHEL (major, minor), arch ->
     sprintf "Red Hat Enterprise Linux® %d.%d (%s)"
             major minor (string_of_arch arch)
  | Ubuntu (ver, dist), X86_64 ->
     sprintf "Ubuntu %s (%s)" ver dist
  | Ubuntu (ver, dist), arch ->
     sprintf "Ubuntu %s (%s) (%s)" ver dist (string_of_arch arch)
  | FreeBSD (major, minor), X86_64 ->
     sprintf "FreeBSD %d.%d" major minor
  | FreeBSD (major, minor), arch ->
     sprintf "FreeBSD %d.%d (%s)" major minor (string_of_arch arch)

  | Windows (6, 1, Client), arch ->
     sprintf "Windows 7 (%s)" (string_of_arch arch)
  | Windows (6, 1, Server), arch ->
     sprintf "Windows Server 2008 R2 (%s)" (string_of_arch arch)
  | Windows (6, 2, Server), arch ->
     sprintf "Windows Server 2012 (%s)" (string_of_arch arch)
  | Windows (6, 3, Server), arch ->
     sprintf "Windows Server 2012 R2 (%s)" (string_of_arch arch)
  | Windows (10, 0, Server), arch ->
     sprintf "Windows Server 2016 (%s)" (string_of_arch arch)
  | Windows _, _ -> assert false

and notes_of_os os arch nvram =
  let args = ref [] in
  let add arg = args := arg :: !args in

  add (long_name_of_os os arch);
  add "";

  (match os with
   | Alma _ ->
      add "This AlmaLinux image contains only unmodified @Core group packages."
   | CentOS _ ->
      add "This CentOS image contains only unmodified @Core group packages."
   | CentOSStream _ ->
      add "This CentOS Stream image contains only unmodified @Core group packages."
   | Debian _ ->
      add "This is a minimal Debian install."
   | Fedora _ ->
      add "This Fedora image contains only unmodified @Core group packages.";
      add "";
      add "Fedora and the Infinity design logo are trademarks of Red Hat, Inc.";
      add "Source and further information is available from http://fedoraproject.org/"
   | RHEL _ -> assert false (* cannot happen, see caller *)
   | Ubuntu _ ->
      add "This is a minimal Ubuntu install."
   | FreeBSD _ ->
      add "This is an all-default FreeBSD install."
   | Windows _ ->
      add "This is an unattended Windows install.";
      add "";
      add "You must have an MSDN subscription to use this image."
  );
  add "";

  (* Specific notes for particular versions. *)
  let reconfigure_ssh_host_keys_debian () =
    add "This image does not contain SSH host keys.  To regenerate them use:";
    add "";
    add "    --firstboot-command \"dpkg-reconfigure openssh-server\"";
    add "";
  in
  let fix_serial_console_debian () =
    add "The serial console is not working in this image.  To enable it, do:";
    add "";
    add "    --edit '/etc/default/grub:";
    add "    s/^GRUB_CMDLINE_LINUX_DEFAULT=.*/GRUB_CMDLINE_LINUX_DEFAULT=\"console=tty0 console=ttyS0,115200n8\"/' \\";
    add "    --run-command update-grub";
    add ""
  in
  let builder_account_warning () =
    add "IMPORTANT WARNING:";
    add "It seems to be impossible to create an Ubuntu >= 14.04 image using";
    add "preseed without creating a user account.  Therefore this image";
    add "contains a user account 'builder'.  I have disabled it, so that";
    add "people who don't read release notes don't get caught out, but you";
    add "might still wish to delete it completely.";
    add ""
  in
  (match os with
   | CentOS (6, _) ->
      add "‘virt-builder centos-6’ will always install the latest 6.x release.";
      add ""
   | Debian ((8|9), _) ->
      reconfigure_ssh_host_keys_debian ();
   | Debian _ ->
      add "This image is so very minimal that it only includes an ssh server";
      reconfigure_ssh_host_keys_debian ();
   | Ubuntu ("16.04", _) ->
      builder_account_warning ();
      fix_serial_console_debian ();
      reconfigure_ssh_host_keys_debian ();
   | Ubuntu (ver, _) when ver >= "14.04" ->
      builder_account_warning ();
      reconfigure_ssh_host_keys_debian ();
   | Ubuntu _ ->
      reconfigure_ssh_host_keys_debian ();
   | _ -> ()
  );

  (match nvram with
   | Some vars ->
      add "You will need to use the associated UEFI NVRAM variables file:";
      add (sprintf "    http://libguestfs.org/download/builder/%s" vars);
      add "";
   | None -> ()
  );

  add "This template was generated by a script in the libguestfs source tree:";
  add "    builder/templates/make-template.ml";
  add "Associated files used to prepare this template can be found in the";
  add "same directory.";

  List.rev !args

and read_revision filename =
  match (try Some (open_in filename) with Sys_error _ -> None) with
  | None -> `No_file
  | Some chan ->
     let r = ref `No_revision in
     let rex = Str.regexp "^revision=\\([0-9]+\\)$" in
     (try
       let rec loop () =
         let line = input_line chan in
         if Str.string_match rex line 0 then (
           r := `Revision (int_of_string (Str.matched_group 1 line));
           raise End_of_file
         );
         loop ()
       in
       loop ()
     with End_of_file -> ()
     );
     close_in chan;
     !r

and sha512sum_of_file filename =
  let cmd = sprintf "sha512sum %s | awk '{print $1}'" (quote filename) in
  let chan = Unix.open_process_in cmd in
  let line = input_line chan in
  let pstat = Unix.close_process_in chan in
  check_process_status_for_errors pstat;
  line

and size_of_file filename = (Unix.stat filename).Unix.st_size

and open_guest ?(mount = false) filename =
  let g = new Guestfs.guestfs () in
  g#add_drive_opts ~format:"raw" filename;
  g#launch ();

  let roots = g#inspect_os () in
  if Array.length roots = 0 then (
    eprintf "%s: cannot inspect this guest - this may mean guest installation failed\n" prog;
    exit 1
  );

  if mount then (
    let root = roots.(0) in
    let mps = g#inspect_get_mountpoints root in
    let cmp (a,_) (b,_) = compare (String.length a) (String.length b) in
    let mps = List.sort cmp mps in
    List.iter (fun (mp, dev) -> g#mount dev mp) mps
  );

  g

and check_process_status_for_errors = function
  | Unix.WEXITED 0 -> ()
  | Unix.WEXITED i ->
     eprintf "command exited with %d\n%!" i;
     exit 1
  | Unix.WSIGNALED i ->
     eprintf "command killed by signal %d\n%!" i;
     exit 1
  | Unix.WSTOPPED i ->
     eprintf "command stopped by signal %d\n%!" i;
     exit 1

and random8 =
  let chars = "abcdefghijklmnopqrstuvwxyz0123456789" in
  fun () ->
  String.concat "" (
    List.map (
      fun _ ->
        let c = Random.int 36 in
        let c = chars.[c] in
        String.make 1 c
      ) [1;2;3;4;5;6;7;8]
    )

let () = main ()
