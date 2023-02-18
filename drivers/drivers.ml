(* virt-drivers
 * Copyright (C) 2009-2023 Red Hat Inc.
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
open Getopt.OptionName
open DOM

open Printf

let parse_cmdline () =
  let blocksize = ref 0 in
  let domain = ref None in
  let file = ref None in
  let libvirturi = ref "" in
  let format = ref "auto" in

  let set_file arg =
    if !file <> None then
      error (f_"--add option can only be given once");
    let uri =
      try URI.parse_uri arg
      with URI.Parse_failed ->
        error (f_"error parsing URI '%s'. \
                  Look for error messages printed above.") arg in
    file := Some uri
  and set_domain dom =
    if !domain <> None then
      error (f_"--domain option can only be given once");
    domain := Some dom
  in

  let argspec = [
    [ S 'a'; L"add" ], Getopt.String (s_"file", set_file), s_"Add disk image file";
    [ L"blocksize" ], Getopt.Set_int ("512|4096", blocksize), s_"Set disk sector size";
    [ S 'c'; L"connect" ], Getopt.Set_string (s_"uri", libvirturi), s_"Set libvirt URI";
    [ S 'd'; L"domain" ], Getopt.String (s_"domain", set_domain), s_"Set libvirt guest name";
    [ L"format" ], Getopt.Set_string (s_"format", format), s_"Format of input disk";
  ] in
  let usage_msg =
    sprintf (f_"\
%s: detect bootloader, kernel and drivers inside guest

A short summary of the options is given below.  For detailed help please
read the man page virt-drivers(1).
")
      prog in
  let opthandle = create_standard_options argspec ~key_opts:true usage_msg in
  Getopt.parse opthandle.getopt;

  (* Check -a and -d options. *)
  let file = !file in
  let domain = !domain in
  let libvirturi = match !libvirturi with "" -> None | s -> Some s in
  let add =
    match file, domain with
    | None, None ->
      error (f_"you must give either -a or -d options.  \
                Read virt-drivers(1) man page for further information.")
    | Some _, Some _ ->
      error (f_"you cannot give -a and -d options together.  \
                Read virt-drivers(1) man page for further information.")
    | None, Some dom ->
      fun (g : Guestfs.guestfs) ->
        let readonlydisk = "ignore" (* ignore CDs, data drives *) in
        ignore (g#add_domain
                  ~readonly:true ~allowuuid:true ~readonlydisk
                  ?libvirturi dom)
    | Some uri, None ->
      fun g ->
        let { URI.path; protocol; server; username; password } = uri in
        let format = match !format with "auto" -> None | s -> Some s in
        let blocksize = match !blocksize with 0 -> None | i -> Some i in
        g#add_drive
          ~readonly:true ?blocksize ?format ~protocol ?server ?username
          ?secret:password path
  in

  add, opthandle.ks

let rec do_detection g roots =
  let comment = Comment generated_by in
  let firmware, firmware_xml = do_detect_firmware g in
  let oses = List.map (fun root -> do_detect_os g root firmware) roots in
  let doc : DOM.doc =
    doc "operatingsystems" [] (comment :: firmware_xml @ oses) in
  doc

and do_detect_firmware g =
  let firmware = Firmware.detect_firmware g in
  let xml =
    match firmware with
    | Firmware.I_BIOS ->
       [ e "firmware" ["type", "bios"] [] ]
    | Firmware.I_UEFI esps ->
       List.map (fun esp -> e "firmware" ["type", "uefi"] [ PCData esp ])
         esps in
  firmware, xml

and do_detect_os g root firmware =
  let body = ref [] in

  (* Display some of the standard virt-inspector fields. *)
  List.push_back body (e "root" [] [ PCData root ]);
  let typ = g#inspect_get_type root in
  if typ <> "unknown" then
    List.push_back body (e "name" [] [ PCData typ ]);

  let adds fn field =
    let v = fn root in
    if v <> "unknown" then
      List.push_back body (e field [] [ PCData v ]);
  and addi fn field =
    let v = fn root in
    List.push_back body (e field [] [ PCData (string_of_int v) ]);
  in
  adds g#inspect_get_arch               "arch";
  adds g#inspect_get_distro             "distro";
  adds g#inspect_get_product_name       "product_name";
  adds g#inspect_get_product_variant    "product_variant";
  addi g#inspect_get_major_version      "major_version";
  addi g#inspect_get_minor_version      "minor_version";
  adds g#inspect_get_package_format     "package_format";
  adds g#inspect_get_package_management "package_management";
  adds g#inspect_get_build_id           "build_id";
  adds g#inspect_get_osinfo             "osinfo";

  (* Now mount up the disks in order to detect bootloader and kernels. *)
  let mps = g#inspect_get_mountpoints root in
  let cmp (a,_) (b,_) = compare (String.length a) (String.length b) in
  let mps = List.sort cmp mps in
  List.iter (fun (mp, dev) -> g#mount_ro dev mp) mps;

  (match typ with
   | "linux" ->
      (* XXX This shouldn't be necessary.  Linux_* modules should do it. *)
      g#aug_init "/" 1;
      let bootloader = do_detect_linux_bootloader g root firmware in
      List.push_back body bootloader
   | "windows" ->
      let drivers = do_detect_windows_drivers g root in
      List.push_back body drivers
   | _ -> ()
  );

  g#umount_all ();

  e "operatingsystem" [] !body

and do_detect_linux_bootloader g root firmware =
  let bootloader = Linux_bootloaders.detect_bootloader g root firmware in
  let bl_name = bootloader#name in
  let bl_config = bootloader#get_config_file () in
  let kernels = do_detect_linux_kernels g root bootloader in
  e "bootloader" ["type", bl_name; "config", bl_config] kernels

and do_detect_linux_kernels g root bootloader =
  let apps = g#inspect_list_applications2 root in
  let apps = Array.to_list apps in
  let kernels = Linux_kernels.detect_kernels g root bootloader apps in
  List.map kernel_info_to_xml kernels

and kernel_info_to_xml { Linux_kernels.ki_name; ki_version;
                         ki_arch; ki_vmlinuz; ki_initrd; ki_modpath;
                         ki_modules; ki_supports_virtio_blk;
                         ki_supports_virtio_net; ki_supports_virtio_rng;
                         ki_supports_virtio_balloon;
                         ki_supports_isa_pvpanic;
                         ki_supports_virtio_socket;
                         ki_is_xen_pv_only_kernel;
                         ki_is_debug; ki_config_file } =
  let body = ref [] in
  List.push_back body (e "name" []    [ PCData ki_name ]);
  List.push_back body (e "version" [] [ PCData ki_version ]);
  List.push_back body (e "arch" []    [ PCData ki_arch ]);
  List.push_back body (e "vmlinuz" [] [ PCData ki_vmlinuz ]);
  List.may_push_back body
    (Option.map (fun v -> e "initrd" [] [ PCData v ]) ki_initrd);
  List.push_back body (e "modules_path" [] [ PCData ki_modpath ]);
  List.push_back body (e "modules" []
                         (List.map (fun m -> e "module" [] [ PCData m ])
                            (List.sort compare ki_modules)));
  if ki_supports_virtio_blk then
    List.push_back body (e "supports_virtio_blk" [] []);
  if ki_supports_virtio_net then
    List.push_back body (e "supports_virtio_net" [] []);
  if ki_supports_virtio_rng then
    List.push_back body (e "supports_virtio_rng" [] []);
  if ki_supports_virtio_balloon then
    List.push_back body (e "supports_virtio_balloon" [] []);
  if ki_supports_isa_pvpanic then
    List.push_back body (e "supports_isa_pvpanic" [] []);
  if ki_supports_virtio_socket then
    List.push_back body (e "supports_virtio_socket" [] []);
  if ki_is_xen_pv_only_kernel then
    List.push_back body (e "is_xen_pv_only_kernel" [] []);
  if ki_is_debug then
    List.push_back body (e "debug_kernel" [] []);
  List.may_push_back body
    (Option.map (fun v -> e "config_file" []  [ PCData v ]) ki_config_file);

  e "kernel" [] !body

and do_detect_windows_drivers g root =
  let drivers = Windows_drivers.detect_drivers g root in
  let drivers = List.map windows_driver_to_xml drivers in
  e "drivers" [] drivers

and windows_driver_to_xml { Windows_drivers.name; hwassoc } =
  e "driver" [] (
    e "name" [] [PCData name] :: List.map windows_hardware_to_xml hwassoc
  )

and windows_hardware_to_xml = function
  | Windows_drivers.PCI { pci_class; pci_vendor; pci_device;
                          pci_subsys; pci_rev } ->
     let attrs = ref [] in
     List.may_push_back attrs
       (Option.map (fun v -> ("class", sprintf "%06LX" v)) pci_class);
     List.may_push_back attrs
       (Option.map (fun v -> ("vendor", sprintf "%04LX" v)) pci_vendor);
     let vendorname = get_pci_vendor pci_vendor in
     List.may_push_back attrs
       (Option.map (fun v -> "vendorname", v) vendorname);
     List.may_push_back attrs
       (Option.map (fun v -> ("device", sprintf "%04LX" v)) pci_device);
     let devicename = get_pci_device pci_vendor pci_device in
     List.may_push_back attrs
       (Option.map (fun v -> "devicename", v) devicename);
     List.may_push_back attrs
       (Option.map (fun v -> ("subsystem", sprintf "%08LX" v)) pci_subsys);
     List.may_push_back attrs
       (Option.map (fun v -> ("revision", sprintf "%02LX" v)) pci_rev);
     e "pci" !attrs []

  | HID { hid_vendor; hid_product; hid_rev; hid_col; hid_multi } ->
     let attrs = ref [] in
     List.may_push_back attrs
       (Option.map (fun v -> ("vendor", sprintf "%04LX" v)) hid_vendor);
     List.may_push_back attrs
       (Option.map (fun v -> ("product", sprintf "%04LX" v)) hid_product);
     List.may_push_back attrs
       (Option.map (fun v -> ("revision", sprintf "%02LX" v)) hid_rev);
     List.may_push_back attrs
       (Option.map (fun v -> ("collection", sprintf "%02LX" v)) hid_col);
     List.may_push_back attrs
       (Option.map (fun v -> ("identifier", sprintf "%02LX" v)) hid_multi);
     e "hid" !attrs []

  | USB { usb_vendor; usb_product; usb_rev; usb_multi } ->
     let attrs = ref [] in
     List.may_push_back attrs
       (Option.map (fun v -> ("vendor", sprintf "%04LX" v)) usb_vendor);
     let vendorname = get_usb_vendor usb_vendor in
     List.may_push_back attrs
       (Option.map (fun v -> "vendorname", v) vendorname);
     List.may_push_back attrs
       (Option.map (fun v -> ("product", sprintf "%04LX" v)) usb_product);
     let productname = get_usb_device usb_vendor usb_product in
     List.may_push_back attrs
       (Option.map (fun v -> "productname", v) productname);
     List.may_push_back attrs
       (Option.map (fun v -> ("revision", sprintf "%02LX" v)) usb_rev);
     List.may_push_back attrs
       (Option.map (fun v -> ("identifier", sprintf "%02LX" v)) usb_multi);
     e "usb" !attrs []

  | Other path ->
     Comment (sprintf "unknown DeviceId: %s" (String.concat "\\" path))

and get_pci_vendor v = get_hwdata'1 Hwdata.pci_vendor v
and get_pci_device v d = get_hwdata'2 Hwdata.pci_device v d
and get_usb_vendor v = get_hwdata'1 Hwdata.usb_vendor v
and get_usb_device v d = get_hwdata'2 Hwdata.usb_device v d

and get_hwdata'1 f = function
  | Some i64 when i64 >= 0_L && i64 <= 0xffff_L ->
     let i32 = Int64.to_int32 i64 in
     f i32
  | _ -> None

and get_hwdata'2 f v d =
  match v, d with
  | Some v64, Some d64 when v64 >= 0_L && v64 <= 0xffff_L &&
                            d64 >= 0_L && d64 <= 0xffff_L ->
     let v32 = Int64.to_int32 v64 and d32 = Int64.to_int32 d64 in
     f v32 d32
  | _ -> None

(* Main program. *)
let main () =
  let add, ks = parse_cmdline () in

  (* Connect to libguestfs. *)
  let g = open_guestfs () in
  add g;
  g#set_network (key_store_requires_network ks);
  g#launch ();

  (* Decrypt the disks. *)
  inspect_decrypt g ks;

  let roots = g#inspect_os () in
  let roots = Array.to_list roots in

  (* Can't call inspect_mount_root here (ie. normal processing of
   * the -i option) because it can only handle a single root.
   *)

  (* Do the detection. *)
  let doc : DOM.doc = do_detection g roots in
  DOM.doc_to_chan stdout doc;

  (* Shutdown. *)
  g#shutdown ();
  g#close ()

let () = run_main_and_handle_errors main
