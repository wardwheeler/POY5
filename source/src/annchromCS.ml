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

(** A annotated chromosome character set implementation. 
* The annotated chromosome character set allows rearrangements *)

let () = SadmanOutput.register "AnnchromCS" "$Revision$"

let debug = false
let debug_assign_single = false
let debug_distance = false

let fprintf = Printf.fprintf

module IntMap = All_sets.IntegerMap
module IntSet = All_sets.Integers
type meds_t = Annchrom.meds_t


(** An annotated chromosome character set *)
type t = { 
    meds : meds_t IntMap.t; (** a set of annotated chromosome characters *)
    costs : float IntMap.t;
    recosts : float IntMap.t;
    total_cost : float;          (** The total cost of the character set *)
    total_recost : float;        (** The total recost of the character set *)
    subtree_cost : float;           (** The total_cost of subtree root in this node*)
    subtree_recost : float;      (** The total subtree recost of the character set *)
    c2_full : Cost_matrix.Two_D.m;    (** The two dimensional cost matrix to be used in the character set *)
    c2_original : Cost_matrix.Two_D.m;    (** original input cost matrix *)
    c3 : Cost_matrix.Three_D.m;  (** The three dimensional cost matrix to be used in the character set *)
    alph : Alphabet.a;           (** The alphabet of the sequence set *)
    annchrom_pam : Data.dyna_pam_t;
    code : int;                  (** The set code *)
}

let cardinal x = IntMap.fold (fun _ _ x -> x + 1) x.meds 0

let print (data : t) = 
    Printf.printf "[ total_cost = %f; total_recost = %f; subtree_recost = %f ]\n%!"
                  data.total_cost data.total_recost data.subtree_recost;
    IntMap.iter
        (fun key item ->
            Printf.printf "[key:%d\n\t%!" key;
            Annchrom.print item;
            Printf.printf "]\n%!";)
        data.meds

let printmedlist alpha x = Printf.printf "%s \n%!" (Annchrom.to_string x alpha) 

(** [of_array spec arr chcode tcode num_taxa] 
* creates an annotated chromosome set
* from an array of sequences [arr] *)
let of_array spec arr chcode tcode num_taxa = 
    let adder (meds, costs, recosts) (chrom, chrom_code) = 

        let med = Annchrom.init_med chrom.Data.seq_arr 
            spec.Data.tcm2d_full spec.Data.tcm2d_original spec.Data.alph spec.Data.pam tcode num_taxa
        in 
        (IntMap.add chrom_code med meds), 
        (IntMap.add chrom_code 0.0 costs),
        (IntMap.add chrom_code 0.0 recosts)
    in
    let meds, costs, recosts = 
        let empty = IntMap.empty in
        Array.fold_left adder (empty, empty, empty) arr
    in
    {
        meds = meds;
        costs = costs;
        recosts = recosts;
        total_cost = 0.0;
        total_recost = 0.0;
        subtree_cost = 0.0;
        subtree_recost = 0.0;
        c2_full = spec.Data.tcm2d_full;
        c2_original = spec.Data.tcm2d_original;
        c3 = spec.Data.tcm3d;
        alph = spec.Data.alph;
        annchrom_pam = spec.Data.pam;
        code = chcode;
    }

(** [of_list spec arr chcode tcode num_taxa] creates 
* an annotated chromosome set from a list of sequences [lst] *)
let of_list spec lst chcode tcode num_taxa = 
    let arr = Array.of_list lst in
    of_array spec arr chcode tcode num_taxa

(** [to_list t] returns a list of annotated chromosome characters 
* from a set of annotated chromosome characters *)
let to_list t =
    IntMap.fold (fun code med acc -> (med, code) :: acc) t.meds []

(** [same_codes a b] returns true if code set of [a] 
* is the same to code set of [b], otherwise false *)
let same_codes a b =
    let checker x _ res = res && (IntMap.mem x b) in
    IntMap.fold checker a true


(** [median2 a b] returns the median set 
* between annotated chromosome character sets [a] and [b] *)
let median2 (a : t) (b : t) =
    (* We will use imperative style for this function *)
    let empty = IntMap.empty in
    let median code (meda : meds_t) (medians, costs, recosts, total_cost, total_recost) = 
        let medb : meds_t = IntMap.find code b.meds in
        let medab = Annchrom.find_meds2 meda medb in
        let new_median = IntMap.add code medab medians 
        and new_costs = 
            IntMap.add code (float_of_int medab.Annchrom.total_cost) costs  
        and new_recosts = 
            IntMap.add code (float_of_int medab.Annchrom.total_recost) recosts  
        and new_total_cost = total_cost + medab.Annchrom.total_cost 
        and new_total_recost = total_recost + medab.Annchrom.total_recost in
        new_median, new_costs, new_recosts, new_total_cost, new_total_recost
    in
    let medab_map, new_costs, new_recosts, total_cost, total_recost = 
        IntMap.fold median a.meds (empty, empty, empty, 0, 0)
    in
    let subtree_recost = a.subtree_recost +. b.subtree_recost +. (float_of_int total_recost) in 
    let subtree_cost = a.subtree_cost +. b.subtree_cost +. (float_of_int total_recost) in 
    if debug then Printf.printf "end of annchromCS.median2 \n%!";
    { a with meds = medab_map; costs = new_costs; recosts = new_recosts;
          total_cost = float_of_int total_cost; 
          total_recost = float_of_int total_recost;
          subtree_cost = subtree_cost;
          subtree_recost = subtree_recost;
    }
    

(** [median3 p n c1 c2] returns the median set of
* annotated chromosome character sets [p], [c1] and [c2] *)
let median3 p n c1 c2 =
    if debug then Printf.printf "annchromCS.median3 \n%!";
    let median code  medp res_medians = 
        let med1= IntMap.find code c1.meds in 
        let med2 = IntMap.find code c2.meds in
        
        let medp12 = Annchrom.find_meds3 medp med1 med2 in
          IntMap.add code medp12 res_medians 
    in
    let acc = IntMap.empty in
    let medp12_map = IntMap.fold median p.meds acc in
    if debug then Printf.printf "end of annchromCS.median3 \n%!";
    { n with meds = medp12_map; }
    

(**[get_extra_cost_for_root root] return the extra cost result from non-zero
* diagonal in cost matrix.*)
let get_extra_cost_for_root (a :t) =
    let get_ec code medst acc =
        acc + Annchrom.get_extra_cost_for_root medst a.c2_original 
    in
    let is_identity = Cost_matrix.Two_D.is_identity a.c2_original in
    if is_identity then 0. (*0 diagonal in cost matrix*)
    else (*non-0 diagonal in cost matrix*)
    float_of_int (IntMap.fold get_ec a.meds 0) 


(** [distance a b] returns total distance between 
* two annotated chromosome character sets [a] and [b] *)
let distance (a : t) (b : t)  = 
    let single_distance code meda (acc_cost, acc_recost) =
        let medb = IntMap.find code b.meds in
        if debug_distance then 
        Printf.printf "distance between %s and %s => \n%!" 
        (AnnchromAli.to_formater (List.hd  meda.Annchrom.med_ls) a.alph) 
        (AnnchromAli.to_formater (List.hd medb.Annchrom.med_ls) b.alph);
        let cost, recost = Annchrom.cmp_min_pair_cost meda medb in 
        if debug_distance then Printf.printf "is %d/%d\n%!" cost recost;
        acc_cost + cost, acc_recost + recost
    in
    let cost, _ = IntMap.fold single_distance a.meds (0, 0) in 
    float_of_int cost


(** [max_distance a b] returns total maximum distances
* between two annotated chromosome character sets [a] and [b]*)
let max_distance (a : t) (b : t)  = 
    let single_distance code meda (acc_cost, acc_recost) =
        let medb = IntMap.find code b.meds in
        let cost, recost = Annchrom.cmp_max_pair_cost meda medb in 
        acc_cost + cost, acc_recost + recost
    in
    let cost, _ = IntMap.fold single_distance a.meds (0,0) in 
    float_of_int cost

(** [to_string a] converts the annotated chromosome character set [a]
* into string format *)
let to_string a =
    let builder code med acc =
        let code = string_of_int code in 
        let med_ls = List.map 
            (fun med ->
                 Annchrom.to_string med a.alph) med.Annchrom.med_ls in 
        let seq = String.concat ":" med_ls in 
        acc ^ code ^ ": " ^ seq ^ "; "
    in
    IntMap.fold builder a.meds ""


(* [dist_2 n a b] calculates the cost of joining 
* the node containing annotated chromosome character set [n]
* between two nodes containing [a] and [b]. 
* [a] must be the parent (ancestor) of [b] *)
let dist_2 n a b =
    if debug then Printf.printf "annchromCS.dist_2\n%!";
    let cost_calculator code medb (acc_cost, acc_recost) =
        let medn = IntMap.find code n.meds
        and meda = IntMap.find code a.meds 
        and medb = IntMap.find code b.meds in
        
        let medab : meds_t = Annchrom.find_meds2 meda medb in 
        
        let cost, recost = Annchrom.cmp_min_pair_cost medn medab in 
        acc_cost + cost, acc_recost + recost
    in
    let cost, _ =     IntMap.fold cost_calculator b.meds (0,0) in 
    if debug then Printf.printf "end of annchromCS.dist_2\n%!";
    float_of_int cost


(** [f_codes s c] returns an annotated chromosome character subset
* of annotated chromosome character set [s] whose codes are 
* also in annotated chromosome character set [c] *)
let f_codes s c = 
    let check x = All_sets.Integers.mem x c in
    let adder x y acc = 
        if check x then IntMap.add x y acc 
        else acc
    in
    let n_meds = IntMap.fold adder s.meds IntMap.empty
    and n_costs = IntMap.fold adder s.costs IntMap.empty in
    { s with meds = n_meds; costs = n_costs}

(** [f_codes_comp s c] returns an annotated chromosome character subset
* of annotated chromosome character set [s] whose codes are NOT
* also in annotated chromosome character set [c] *)
let f_codes_comp s c = 
    let check x = not (All_sets.Integers.mem x c) in
    let adder x y acc = 
        if check x then IntMap.add x y acc 
        else acc
    in
    let n_meds = IntMap.fold adder s.meds IntMap.empty
    and n_costs = IntMap.fold adder s.costs IntMap.empty in
    { s with meds = n_meds; costs = n_costs }

(** [compare_data a b] compares annotated chromosome character
* set [a] and [b]. Returns 0 if they are the same, 
* otherwise (-1) or (1) *)
let compare_data a b =
    let comparator code medb acc =
        if acc = 0 then begin
            let meda = IntMap.find code a.meds in
            Annchrom.compare meda medb
        end else acc
    in
    IntMap.fold comparator b.meds 0


(** [readjust to_adjust modified ch1 ch2 parent mine] returns
* the readjusted median set [mine] of three annotated chromosome character
* sets [ch1], [ch2] and [parent] *)
let readjust to_adjust modified ch1 ch2 parent mine =
    if debug then Printf.printf "annchromCS.ml readjust \n%!";
    let empty = IntMap.empty and
            c2_full = parent.c2_full and
            c3 = parent.c3 
    in
    let adjusted code parent_chrom acc =
        let to_adjust =
            match to_adjust with
            | None -> All_sets.Integers.singleton code
            | Some x -> x
        in
        let (modified, res_medians, res_costs, total, totalsum) = acc in
        let my_chrom = IntMap.find code mine.meds
        and ch1_chrom = IntMap.find code ch1.meds
        and ch2_chrom = IntMap.find code ch2.meds in
        if (not (All_sets.Integers.mem code to_adjust)) then 
            let new_costs = IntMap.add code 0. res_costs 
            and new_single = IntMap.add code my_chrom res_medians in
            modified, new_single, new_costs, total, totalsum
        else begin
            let rescost, ressumcost, seqm, changed = 
                Annchrom.readjust_3d ch1_chrom ch2_chrom my_chrom
                    c2_full c3 parent_chrom
            in
            let new_single = IntMap.add code seqm res_medians
            and new_costs = IntMap.add code (float_of_int rescost) res_costs 
            and new_total = total + rescost in
            let new_totalsum = ressumcost + totalsum in
            let modified = 
                if changed then All_sets.Integers.add code modified
                else modified
            in
            modified, new_single, new_costs, new_total, new_totalsum       
        end 
    in 
    let modified, meds, costs, total_cost, total_sum_cost = 
        IntMap.fold adjusted parent.meds (modified, empty, empty, 0, 0)
    in
    let tc = float_of_int total_cost in
    let tsc = float_of_int total_sum_cost in
    if debug then Printf.printf "end of annchromCS.ml readjust \n%!";
    modified, tc, tsc, 
    { mine with meds = meds; costs = costs; total_cost = tc; subtree_cost = tsc; }


(** [to_formatter ref_codes attr t parent_t d] returns
* the map between annotated chromosme character set [t] and its parents
* [parent_t] in the Tag.output format *)
let to_formatter ref_codes attr t (parent_t : t option) d : Xml.xml Sexpr.t list =
    if debug then Printf.printf "annchromCS.to_formatter \n%!";
    let _, state = List.hd attr in 
    let output_annchrom code med acc =
        let med = 
            try
                List.find (fun med -> 
                               IntSet.mem med.AnnchromAli.ref_code  ref_codes
                          ) med.Annchrom.med_ls
            with Not_found -> failwith "Not found med -> to_formatter -> ChromCS"
        in         
        let cost, recost, map = 
            match parent_t with  
            | None -> 0, 0, None
            | Some parent -> begin
                  let parent_med = IntMap.find code parent.meds in   
                  let parent_med = List.find 
                      (fun med -> 
                           IntSet.mem med.AnnchromAli.ref_code ref_codes 
                      ) parent_med.Annchrom.med_ls
                  in                   
                  let cost, recost, map = 
                      match state with
                      | `String "Preliminary" ->
                            AnnchromAli.create_map parent_med med.AnnchromAli.ref_code  
                      | `String "Final" ->
                            AnnchromAli.create_map med parent_med.AnnchromAli.ref_code   
                      | `String "Single" ->
                            let cost, recost, med_ls = AnnchromAli.find_med2_ls med
                                parent_med t.c2_full t.alph t.annchrom_pam in 
                            let med = List.hd med_ls in 
                            let map = AnnchromAli.create_single_map med in               
                            cost, recost, map
                      | _ -> failwith ("to_formatter in annchromCS.ml");
                  in 
                  cost, recost, Some map
              end 
        in  
        let seqs = AnnchromAli.to_formater med t.alph in  
        let name = Data.code_character code d in  
        let cost_str = 
            match state with
            | `String "Single" -> `IntTuple (cost, cost)
            | _ -> `IntTuple (0, cost)
        in 
        let module T = Xml.Characters in
        (PXML 
            -[T.chromosome]
                (* Attributes *)
                ([T.name] = [`String name])
                ([T.cost] = [ cost_str])
                ([T.recost] = [`Int recost])
                ([T.definite] = [`Bool (cost > 0)])
                ([T.ref_code] = [`Int med.AnnchromAli.ref_code])
                ([attr])

                (* Contents *)
                { match map with
                | None -> (PXML ---)
                | Some map -> `Single map }

                -[T.sequence] [`String seqs] --
            --) :: acc
    in
    IntMap.fold output_annchrom t.meds []


(** [get_active_ref_code t] returns active reference codes
* of annotated chromosome character set [t]. 
* One active reference code for one annotated chromosome character *)
let get_active_ref_code t = 
    IntMap.fold 
        (fun _ meds (acc_ref_code, acc_child_ref_code) ->
             let ref_code, child1_ref_code, child2_ref_code = 
                 Annchrom.get_active_ref_code meds 
             in
             IntSet.add ref_code acc_ref_code,
             IntSet.add child2_ref_code (IntSet.add child1_ref_code acc_child_ref_code)  
        ) t.meds (IntSet.empty, IntSet.empty)


(** [to_single ref_codes root single_parent mine] returns
* the single states of annotated chromosome character set [mine] *) 
let to_single ref_codes (root : t option) single_parent mine = 
    if debug_assign_single then
     Printf.printf "annchromCS.ml to_single,previous_total_cost=%f -> \n%!"
     mine.total_cost;
    let printmedlist alpha x = Printf.printf "%s \n%!" (Annchrom.to_string x alpha) in
    let previous_total_cost = mine.total_cost in 
    let c2_full = mine.c2_full in 
    let c2_original = mine.c2_original in 
    let median code med (acc_meds, acc_costs, acc_recosts, acc_total_cost) =    
        if debug_assign_single then 
                Printf.printf "pick one of mine.med_ls(len=%d) as amed:\n%!"
                (List.length med.Annchrom.med_ls);
        let amed = 
            try
                List.find (fun med -> 
                               IntSet.mem med.AnnchromAli.ref_code ref_codes
                          ) med.Annchrom.med_ls
            with Not_found ->
                if debug_assign_single then Printf.printf "[pick the head]%!";
                (List.hd med.Annchrom.med_ls)
                (*failwith "Not found med -> to_formatter -> AnnchromCS"*)
        in  
        if debug_assign_single then printmedlist mine.alph amed;
        (* when median =1, there is only one member in parent_med.med_ls*)
        
        let parent_med = IntMap.find code single_parent.meds in  
        if debug_assign_single then 
            Printf.printf "pick one from parent.med_ls(len=%d) as aparent_med =\n%!"
            (List.length parent_med.Annchrom.med_ls);
        let aparent_med = 
            try
                List.find (fun med -> 
                               IntSet.mem med.AnnchromAli.ref_code ref_codes 
                          ) parent_med.Annchrom.med_ls
            with Not_found ->
                if debug_assign_single then Printf.printf "[pick the head]%!";
                List.hd parent_med.Annchrom.med_ls
        in
        if debug_assign_single then printmedlist mine.alph aparent_med;
        let cost,  recost, single_seq_arr =             
            match root with
            | Some root ->
                  let single_root = AnnchromAli.to_single_root amed
                      aparent_med.AnnchromAli.ref_code c2_full 
                  in 
                  0, 0, single_root
            | None ->
                    let single_seq_arr = 
                      AnnchromAli.assign_single_nonroot aparent_med amed
                      amed.AnnchromAli.ref_code c2_full med.Annchrom.annchrom_pam in           
                   if debug_assign_single then begin
                        Printf.printf " call AnnchromAli.assign_single_nonroot,\
                        make single_seq_arr out of aparent_med and amed  = \n%!";
                        Array.iter AnnchromAli.printSeq single_seq_arr;
                   end;
                  let single_med = 
                      {amed with 
                           AnnchromAli.seq_arr = Array.mapi 
                              (fun idx seqt -> 
                                   {seqt with AnnchromAli.seq =
                                           (Sequence.delete_gap single_seq_arr.(idx))}
                              ) amed.AnnchromAli.seq_arr
                      }
                  in
                  let cost, recost = AnnchromAli.cmp_cost single_med aparent_med
                  c2_original mine.alph med.Annchrom.annchrom_pam in 
                  if debug then begin
                      Printf.printf "let single_med become amed with seq_arr replaced by single_seq_arr \n compute the cost between single_med = ";
                    printmedlist mine.alph single_med;
                    Printf.printf " and aparent_med =  ";
                    printmedlist mine.alph aparent_med;
                    Printf.printf "cost = %d \n" cost ;
                  end;
                  cost, recost, single_seq_arr
        in 
        let single_med = AnnchromAli.change_to_single amed single_seq_arr
        c2_full in
        let single_med = {med with Annchrom.med_ls = [single_med]} in 
        let new_single = IntMap.add code single_med acc_meds in
        let new_costs = IntMap.add code (float_of_int cost) acc_costs in 
        let new_recosts = IntMap.add code (float_of_int recost) acc_recosts in
        new_single, new_costs, new_recosts, (acc_total_cost + cost)
    in
    let meds, costs,  recosts, total_cost = 
        match root with
        | Some root ->
              IntMap.fold median root.meds (IntMap.empty, IntMap.empty, IntMap.empty, 0)
        | None ->
              IntMap.fold median mine.meds (IntMap.empty, IntMap.empty, IntMap.empty, 0)
    in
    let subtree_recost = 
        match root with 
        | Some root -> root.subtree_recost
        | None -> mine.subtree_recost 
    in
    if debug then
    Printf.printf "<-- end of annchromCS.ml to_single\n %!";
    previous_total_cost, float_of_int total_cost, 
    {mine with meds = meds; 
         costs = costs;
         recosts = recosts;
         total_cost = float_of_int total_cost;
         subtree_recost = subtree_recost }


(** [copy_chrom_map s_ch d_ch] copies the chromosome
* map of annotated chromosome set [s_ch] 
* to annotated chromosome set [d_ch] *)
let copy_chrom_map s_ch d_ch =
    let copied_meds = IntMap.mapi 
        (fun code ad_ch ->
             let as_ch = IntMap.find code s_ch.meds in 
             let copied_ad = Annchrom.copy_chrom_map as_ch ad_ch in 
             copied_ad
        ) d_ch.meds
    in 
    {d_ch with meds = copied_meds}
