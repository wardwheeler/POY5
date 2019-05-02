(* POY 5.1.1. A phylogenetic analysis program using Dynamic Homologies.       *)
(* Copyright (C) 2011  Andrés Varón, Lin Hong, Nicholas Lucaroni, Ward Wheeler*)
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

module P : sig
    type datatype = 
         DStandard | Dna | Rna | Nucleotide | Protein | Continuous 

    type item = 
         Min | Max | Median | Average | Variance | Stderror | SampleSize |
        States 

    type statesformat =
         StatesPresent | Individuals | Count | Frequency 

    type triangleformat =  Lower | Upper | Both 

    type format_options =  
        | Datatype of datatype  
        | RespectCase
        | FMissing of string
        | Gap of string
        | Symbols of string  (** still need to parse the symbols *)
        | Equate of string   (** still need to parse the tuples *)
        | MatchChar of string
        | Labels of bool
        | Transpose
        | Interleave
        | Items of item
        | StatesFormat of statesformat
        | Triangle of triangleformat
        | Tokens of bool 

    type charset = 
        | Range  of (int * int option * int)
        | Single of int
        | Name   of string

    type char_data = {
        char_taxon_dimensions : string option;
        char_char_dimensions : string;
        char_format : format_options list;
        char_eliminate : charset option;
        char_taxlabels : string list;
        char_statelabels : (string * string * string list) list;
        char_charlabels : string list;
        char_charstates : (string * string list) list;
        chars : string;
    }

    type unalg_data = {
        unal_taxon_dimensions : string option;
        unal_format : format_options list;
        unal : string;
    }

    type standard_item = 
         Code of (string * charset list) | IName of (string * charset list) 

    type standard_list = 
        | STDVector of string list | STDStandard of charset list

    type set_type = 
        | Standard of standard_item list | Vector of string list 

    type set_pair =  
        | TaxonSet of charset list
        | CharacterSet of charset list
        | StateSet of charset list
        | TreeSet of charset list
        | CharPartition of set_type
        | TaxPartition of set_type
        | TreePartition of set_type

    type source =  Inline | File | Resource 

    type pictureformat =  Pict | Tiff | Eps | Jpeg | Gif 

    type pictureencoding =  None | UUEncode | BinHex 
    type polytcount =  MinSteps | MaxSteps 
    type gapmode =  Missing | NewState 

    type user_type =  StepMatrix of (string * string list) | CSTree of string 

    type assumption_set = (bool * string * bool * set_type)

    type assumption_items = 
        | Options of (string option * polytcount * gapmode)
        | UserType of (string * user_type)
        | TypeDef of assumption_set
        | WeightDef of assumption_set
        | ExcludeSet of (bool * string * standard_list)
        | AncestralDef of assumption_set

    type likelihood_model = 
        | Model of string
        | Variation of string
        | Variation_Sites of string
        | Variation_Alpha of string
        | Variation_Invar of string
        | Given_Priors of (string * float) list
        | Other_Priors of string 
        | Cost_Mode of string
        | Chars of charset list
        | Parameters of float list
        | Gap_Mode of (string * float option)
        | Files of string

    type character_data =
        | Tree_Names of string list
        | Set_Names of charset list
        | Labeling of (string * float) list 

    type annot_data =
        | Annot_Quality of float
        | Annot_Min of int
        | Annot_Max of int
        | Annot_Min_Percent of float
        | Annot_Max_Percent of float
        | Annot_Coverage of float
        | Annot_Type of [`Mauve | `Default]
        | Annot_Rearrangement of int

    type chrom_data =
        | Chrom_Solver of string
        | Chrom_Locus_Indel of int * float
        | Chrom_Locus_Breakpoint of int
        | Chrom_Locus_Inversion of int
        | Chrom_Approx of bool
        | Chrom_Median of int
        | Chrom_Symmetric of bool
        | Chrom_Annotations of annot_data list

    type genome_data =
        | Genome_Median of int
        | Genome_Indel of int * float
        | Genome_Circular of bool
        | Genome_Breakpoint of int
        | Genome_Distance of float

    type poy_data =  
        | Chrom of chrom_data list * charset list
        | Genome of genome_data list * charset list
            (* we only use the median_solver below *)
        | BreakInv of chrom_data list * charset list
        | CharacterBranch of character_data list
        | Likelihood of likelihood_model list
        | Tcm of (bool * string * standard_item list)
        | GapOpening of (bool * string * standard_item list)
        | DynamicWeight of (bool * string * standard_item list)
        | Level of (bool * string * standard_item list)

    type block = 
        | Taxa of (string * string list) 
        | Characters of char_data 
        | Distances of ((bool * string * string) option * format_options list * string list * string)
        | Ignore of string
        | Unaligned of unalg_data
        | Trees of (string * string) list * string list 
        | Notes of ((set_pair list * source * string) option * (set_pair list *
        pictureformat option * pictureencoding option * source * string) option) 
        | Assumptions of assumption_items list 
        | Error of string
        | Sets of (string * set_pair) list
        | Poy of poy_data list

    type tree_i = 
        | Leaf of (string * (float option * string option))
        | Node of (tree_i list * string option * (float option * string option))


    type tree = string * tree_i

    val print_error : (string -> unit) ref
end

module Grammar : sig
    type token
    val tree : (Lexing.lexbuf -> token) -> Lexing.lexbuf -> P.tree
    val trees : (Lexing.lexbuf -> token) -> Lexing.lexbuf -> P.tree list
    val header : (Lexing.lexbuf -> token) -> Lexing.lexbuf -> unit
    val block : (Lexing.lexbuf -> token) -> Lexing.lexbuf -> P.block
    val symbol_pair : 
        (Lexing.lexbuf -> token) -> Lexing.lexbuf -> (string * string list) 
    val symbol_list : 
        (Lexing.lexbuf -> token) -> Lexing.lexbuf -> string list
end

module Lexer : sig
    exception Eof
    val token : Lexing.lexbuf -> Grammar.token
    val tree_tokens : Lexing.lexbuf -> Grammar.token
end

module File : sig
    type st_type = 
        | STOrdered
        | STUnordered  
        | STSankoff of int array array   (* If Sankoff, the cost matrix to use *)
        | STLikelihood of MlModel.model  (* The ML model to use *)
        | STNCM of int * float * st_type (* current alphabet, previous weight and type *)

    type static_spec = {
        st_filesource : string; (* The file that contained the character originally *)
        st_name : string;       (* The name assigned to the character *)
        st_alph : Alphabet.a;   (* The set of potential character symbols *)
        st_observed : int list; (* The set of observed states *)
        st_normal : int option; (* factor to normalize continuous characters *)
        st_labels : string list;(* The labels assigned to the states *)
        st_weight : float;      (* The character weight *)
        st_type : st_type;      (* The type of character *)
        st_equivalents : (string * string list) list;
                                (* Things that are the same in the input *)
        st_missing : string;       (* The character that represents missing data *)
        st_matchstate : string option; 
            (* The chaaracter that marks the same state as teh first taxon *)
        st_gap : string;            (* The gap representation *)
        st_eliminate : bool;       (* Wether or not the user wants to get rid of it *)
        st_case : bool;       (* Wether or not the user wants be case sensistive *)
        st_used_observed : (int, int) Hashtbl.t option;
        st_observed_used : (int, int) Hashtbl.t option;
    }

    type static_state = [ `Bits of BitSet.t | `List of int list ]  option

    type taxon = string

    type unaligned = (* information to define unaligned data *)
        {   u_weight : float;
            u_opening: int option;
            u_level  : int option;
            u_tcm    : (string * int array array) option;
            u_alph   : Alphabet.a;
            u_model  : MlModel.model option;
            u_data   : (Sequence.s list list list * taxon) list;
            u_pam    : Dyn_pam.dyna_pam_t option;
        }

    type nexus = {
        char_cntr : int ref;
        taxa : string option array;
        characters : static_spec array;
        matrix : static_state array array;
        csets : (string, P.charset list) Hashtbl.t;
        unaligned : unaligned list;
        trees : (string option * Tree.Parse.tree_types list) list;
        branches : (string, (string, (string , float) Hashtbl.t) Hashtbl.t) Hashtbl.t;
        assumptions : (string, string array * float array array) Hashtbl.t;
    }

    val get_character_names : 
        static_spec array -> 
            (string, P.charset list) Hashtbl.t -> P.charset -> string list

    val empty_parsed : unit -> nexus

    val static_state_to_list : 
        [ `Bits of BitSet.t | `List of int list ] -> int list
    (** [spec_of_alph alphabet missing gap] generates a specification that can read
        the elements in the [alphabet] using when the matrix represents [missing]
        data and [gaps] as specified. *)
    val spec_of_alph : Alphabet.a -> string -> string -> static_spec

    (** [to_string v] outputs a string representation of the static_specification [v] *)
    val to_string : static_spec -> string

    (** [to_formatter v] generates a standard [Xml.xml] representation of [to_formatter]. *)
    val to_formatter : static_spec -> Xml.xml

    val make_symbol_alphabet :
        string -> string list ->  (string * string list) list ->
            P.format_options list -> Alphabet.a * (string * string list) list 

    val process_matrix : 
       bool ->
       [ `Hennig | `Nexus | `None ] ->
       static_state array array ->
       string option array ->
       static_spec array ->
       (string -> int) ->
       (int -> int -> static_state -> unit) -> string -> unit

    val find_taxon : string option array -> string -> int

    val process_tree : string -> P.tree

    val of_channel : in_channel -> string -> nexus

    val generate_alphabet : string list -> string -> Alphabet.a

    val generate_parser_friendly :
        (string*string) list -> string option array -> P.tree ->
            string option * Tree.Parse.tree_types list

    val compute_static_priors :
        Alphabet.a -> bool -> float array * int ref * int ref -> float -> static_state -> unit

    val spec_of_alph : Alphabet.a -> string -> string -> static_spec
    val fill_observed : 
       static_spec array ->
       [< `Bits of BitSet.t | `List of All_sets.Integers.elt list ]
       option array array -> unit

end
