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

(* Helper functions *)
let truere = Str.regexp ".*true.*"

let ( --> ) a b = b a

let append a b = b ^ a

let get_option lst str =
    let _, str =
        List.find (fun (a, _) -> Str.string_match (Str.regexp a) str 0) lst
    in
    str

let get_graphics str =
    get_option [(".*tk", "tk"); (".*ocaml", "ocaml"); (".*", "none")] str

let get_interface str =
    get_option
        [(".*gtk", "gtk2"); (".*ncurses", "ncurses"); (".*pdcurses", "pdcurses");
         (".*readline", "readline"); (".*html", "html"); (".*flat", "flat")]
        str

let is_true str = if Str.string_match truere str 0 then  "on" else "off"

let rephrase str = Str.global_replace (Str.regexp " +") "@ " str

(* The Version Values *)
let name = "Black Sabbath"

let major_version = 5

let minor_version = 1

let release_version = 2

let patch_version = Str.global_replace (Str.regexp " +") ""  BuildNumber.build

type release_options = Development | Candidate of int | Official

let release_option = Official

let if_run a f b c = if a then f b c else c

let option_to_string b =
    let build_string = " Build "
    and rcstring = " Release Candidate " in
    match release_option with
        | Official    ->
            b   --> append " ("
                --> append patch_version
                --> append ")"
        | Development ->
            name --> append " Development"
                 --> append build_string
                 --> append patch_version
        | Candidate x ->
            b   --> append rcstring
                --> append (string_of_int x)

let small_version_string =
    let concatenator x acc = acc ^ string_of_int x in
    let dot = "." in
    ""  --> concatenator major_version
        --> append dot
        --> concatenator minor_version
        --> append dot
        --> concatenator release_version

let version_string =
    option_to_string small_version_string

let version_num_string = Printf.sprintf "%d.%d.%d" major_version minor_version release_version

let copyright_authors =
    rephrase ("@[Copyright (C) 2011, 2012, 2013, 2014 Andres Varon, Nicholas Lucaroni, Lin Hong, Ward Wheeler, and the American Museum of Natural History.@]@,")

let warrenty_information =
    rephrase ("@[POY "^ version_num_string ^" comes with ABSOLUTELY NO WARRANTY; This is free software, and you are welcome to redistribute it under the GNU General Public License Version 2, June 1991.@]@,")

let compile_information =
    rephrase ("@[Compiled on " ^ CompileFlags.time
             ^ " with parallel " ^ is_true CompileFlags.str_parallel
             ^ ", interface " ^ get_interface CompileFlags.str_interface
             ^ ", likelihood " ^ is_true CompileFlags.str_likelihood
             ^ ", and concorde " ^ is_true CompileFlags.str_concorde ^ ".@]@,")

let string =
    "@[@[Welcome to @{<b>POY@} " ^ version_string ^ "@]@."
        ^ compile_information ^ copyright_authors ^ warrenty_information ^ "@]@."
