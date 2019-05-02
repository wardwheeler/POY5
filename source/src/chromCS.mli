(* POY 5.1.1. A phylogenetic analysis program using Dynamic Homologies.       *\
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
\* USA                                                                        *)

exception Illegal_Arguments
val fprintf : out_channel -> ('a, out_channel, unit) format -> 'a
module IntMap :
  sig
    type key = int
    type 'a t = 'a All_sets.IntegerMap.t
    val empty : 'a t
    val is_empty : 'a t -> bool
    val add : key -> 'a -> 'a t -> 'a t
    val find : key -> 'a t -> 'a
    val remove : key -> 'a t -> 'a t
    val mem : key -> 'a t -> bool
    val iter : (key -> 'a -> unit) -> 'a t -> unit
    val map : ('a -> 'b) -> 'a t -> 'b t
    val mapi : (key -> 'a -> 'b) -> 'a t -> 'b t
    val fold : (key -> 'a -> 'b -> 'b) -> 'a t -> 'b -> 'b
    val compare : ('a -> 'a -> int) -> 'a t -> 'a t -> int
    val equal : ('a -> 'a -> bool) -> 'a t -> 'a t -> bool
  end
module IntSet :
  sig
    type elt = int
    type t = All_sets.Integers.t
    val empty : t
    val is_empty : t -> bool
    val mem : elt -> t -> bool
    val add : elt -> t -> t
    val singleton : elt -> t
    val remove : elt -> t -> t
    val union : t -> t -> t
    val inter : t -> t -> t
    val diff : t -> t -> t
    val compare : t -> t -> int
    val equal : t -> t -> bool
    val subset : t -> t -> bool
    val iter : (elt -> unit) -> t -> unit
    val fold : (elt -> 'a -> 'a) -> t -> 'a -> 'a
    val for_all : (elt -> bool) -> t -> bool
    val exists : (elt -> bool) -> t -> bool
    val filter : (elt -> bool) -> t -> t
    val partition : (elt -> bool) -> t -> t * t
    val cardinal : t -> int
    val elements : t -> elt list
    val min_elt : t -> elt
    val max_elt : t -> elt
    val choose : t -> elt
    val split : elt -> t -> t * bool * t
  end
type meds_t = Chrom.meds_t
type t = {
  meds : meds_t IntMap.t;
  costs : float IntMap.t;
  recosts : float IntMap.t;
  total_cost : float;
  subtree_cost : float;           (** The total_cost of subtree root in this node*)
  total_recost : float;
  subtree_recost : float;
  c2_full : Cost_matrix.Two_D.m;
  c2_original : Cost_matrix.Two_D.m;
  c3 : Cost_matrix.Three_D.m;
  chrom_pam : Data.dyna_pam_t;
  alph : Alphabet.a;
  code : int;
}

val cardinal : t -> int

val of_array :
  Data.dynamic_hom_spec ->
  (Sequence.s * IntMap.key) array -> int -> int -> int -> t
val of_list :
  Data.dynamic_hom_spec ->
  (Sequence.s * IntMap.key) list -> int -> int -> int -> t
val to_list : t -> (meds_t * IntMap.key) list
val same_codes : 'a IntMap.t -> 'b IntMap.t -> bool
val median2 : t -> t -> t
val median3 : t -> t -> t -> t -> t
val get_extra_cost_for_root : t -> float
val distance : t -> t -> float
val max_distance : t -> t -> float
val to_string : t -> string
val dist_2 : t -> t -> t -> float
val f_codes : t -> All_sets.Integers.t -> t
val f_codes_comp : t -> All_sets.Integers.t -> t
val compare_data : t -> t -> int
val to_formatter :
  string option -> IntSet.t ->
  Xml.attribute list -> t -> t option -> Data.d -> Xml.xml Sexpr.t list
val to_single : IntSet.t -> t option -> t -> t -> float * float * t 
val get_active_ref_code : t -> IntSet.t * IntSet.t
val print : t -> unit
val copy_chrom_map : t -> t -> t

val readjust :
  All_sets.Integers.t option ->
  All_sets.Integers.t -> t -> t -> t -> t -> All_sets.Integers.t * float * float
  * t
