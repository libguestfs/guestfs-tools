(* virt-drivers
 * Copyright (C) 2013-2023 Red Hat Inc.
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

val dir : string option
(** [pkgdatadir] variable defined by hwdata.pc

    This is the name of the directory containing [pci.ids] and
    related files which contain the PCI IDs. *)

val pci_ids : string option
(** Path to the [pci.ids] file.

    Note at runtime this is an optional dependency, so it may
    not at exist even if not [None]. *)

val usb_ids : string option
(** Path to the [usb.ids] file.

    Note at runtime this is an optional dependency, so it may
    not at exist even if not [None]. *)
