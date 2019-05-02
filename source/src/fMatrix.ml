(* POY 5.1.1. A phylogenetic analysis program using Dynamic Homologies.       *)
(* Copyright (C) 2014 Andrés Varón, Lin Hong, Nicholas Lucaroni, Ward Wheeler,*)
(* and the American Museum of Natural History.                                *)
(*                                                                            *)
(* This program is free software; you can redistribute it and/or modify       *)
(* it under the terms of the GNU General Public License as published by       *)
(* the Free Software Foundation; either version 2 of the License, or          *)
(* (at your option) any later version.                                        *)
(*                                                                            *)
(* This program is distributed in the hope that it will be useful,            *)
(* but WITHOUT ANY WARRANTY; without even the implied warranty of             *)
(* MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the              *)
(* GNU General Public License for more details.                               *)
(*                                                                            *)
(* You should have received a copy of the GNU General Public License          *)
(* along with this program; if not, write to the Free Software                *)
(* Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301   *)
(* USA                                                                        *)

let () = SadmanOutput.register "FMatrix" "$Revision"

type m
external create : int -> m = "floatmatrix_CAML_create"

external expand : m -> int -> unit = "floatmatrix_CAML_expand"
external clear : m -> int -> int -> unit = "floatmatrix_CAML_clear"
external random : m -> unit = "floatmatrix_CAML_random" 
external print : m -> unit = "floatmatrix_CAML_print"
external size : m -> int = "floatmatrix_CAML_getsize"
external used : m -> int = "floatmatrix_CAML_getused"
external freeall : m -> unit = "floatmatrix_CAML_freeall"

external register : unit -> unit = "floatmatrix_CAML_register"
let () = register ()

(* some default space *)
let scratch_space = create 200

