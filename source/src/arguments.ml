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

let () = SadmanOutput.register "Arguments" "$Revision$"

(** [just_exit] is used to return to the interactive console after an error; if
    set to true we will exit and not return to an interactive console. This
    setting is modified by the -e option on the command line. To avoid the
    possibility that someone is leaving this out, we take care of it when
    compiled with parallel extensions on. **)
let just_exit =
    IFDEF USEPARALLEL THEN
        ref true
    ELSE
        ref false
    END

(** [only_run_argument_script] forces the application to run the script and then
    exit, and not wait for user input. This is different then the -e option as
    that is only triggered from an error state, this option is useful when
    someone forgets the exit() command in their script. *)
let only_run_argument_script =
    IFDEF USEPARALLEL THEN
        ref true
    ELSE
        ref false
    END

let default_dump_file = "ft_output.poy"

let dump_file = ref default_dump_file

let input : [`Inlined of string | `Filename of string] list ref = ref []

let change_working_directory str =
    try Sys.chdir str 
    with | err ->
        let error_message =
            if Sys.is_directory str then
                "Failed changing working directory to '" ^ str ^"'. I may not have permissions to access it."
            else if Sys.file_exists str then
                "Failed changing working directory to a file, '" ^ str ^ "'. Please specify a directory."
            else
                "Attempting to change working directory to '" ^ str ^ "' failed.  It may not exist."
        in
        prerr_endline error_message;
        exit 1

let process_poy_plugin plugin =
IFDEF USE_NATIVEDYNLINK THEN
    if Sys.file_exists plugin then 
        let extension = if Dynlink.is_native then "cmxs" else "cmo" in
        if Filename.check_suffix plugin extension then
            Dynlink.loadfile plugin
        else
            failwith ("A plugin for this executable must have extension " ^ extension)
    else 
        failwith ("Could not find KML plugin " ^ plugin)
ELSE
    failwith "This version of POY was compiled without plugin support"
END

let anon_fun kind str = match kind with
    | `Inlined -> input := (`Inlined str) :: !input
    | `Filename -> input := (`Filename str) :: !input


(** Defines the command line options for poy. Descriptions are inlined below *)
let parse_list = [
    ("-w", Arg.String change_working_directory, "Run poy in the specified working directory."); 
    ("-e", Arg.Unit (fun () -> just_exit := true), "Exit upon error.");
    ("-d", Arg.String (fun str -> dump_file := str), "Filename to dump program state in case of an error");
    ("-q", Arg.Unit (fun () -> only_run_argument_script := true), "Don't wait for input other than the program argument script.");
    ("-no-output-xml", Arg.Unit (fun () -> SadmanOutput.do_sadman := false), "Do not generate the output.xml file.");
    ("-plugin", Arg.String process_poy_plugin, "Load the selected plugins.");
    ("-script", Arg.String (anon_fun `Inlined), "Inlined script to be included in the analysis.")
]

let usage =
    "poy [OPTIONS] filename ..."
