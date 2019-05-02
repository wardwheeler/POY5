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

let () = SadmanOutput.register "Ptree" "$Revision$"

let ndebug = false
let ndebug_break_delta = false
let ndebug_traject = false
let ndebug_traject_spr = false || ndebug_traject
let ndebug_traject_tbr = false || ndebug_traject
let ndebug_traject_summary = false      (* summary of the trajectory *)
let ndebug_jxn_of_handle = false
let debug_wagner_traject = false
let debug_search_fn = false
let odebug = Status.user_message Status.Information

let ( --> ) a b = b a

let failwithf format = Printf.ksprintf (failwith) format

type id = Tree.id

type incremental = [
    | `Children of int
    | `No_Children of int
    | `HandleC of (int * int)
    | `HandleNC of (int * int)
]

type clade_cost = NoCost | Cost of float

let compare_clade_cost x y = match x,y with
    | NoCost, NoCost -> 0
    | Cost x, Cost y -> Pervasives.compare x y
    | NoCost, Cost _ ->  1
    | Cost _, NoCost -> -1

type node = Tree.node
type edge = Tree.edge
type t_status = Tree.t_status

type 'a root_node = ([ `Edge of (int * int) | `Single of int ] * 'a) option

type 'a root = {
    root_median : 'a root_node;
    component_cost : float;
    adjusted_component_cost : float;
}

type ('a, 'b) p_tree = { 
    data : Data.d;
    node_data : 'a All_sets.IntegerMap.t ;
    edge_data : 'b Tree.EdgeMap.t ;
    tree : Tree.u_tree;
    component_root : 'a root All_sets.IntegerMap.t;
    origin_cost : float;
}

type phylogeny = (Node.node_data, unit) p_tree

type cost_type = [ `Adjusted | `Unadjusted ]

let get_data ptree = ptree.data

let set_data ptree data = { ptree with data = data; }

let get_cost clas ptree =
    let get_cost = match clas with
        | `Adjusted -> fun x -> x.adjusted_component_cost
        | `Unadjusted -> fun x -> x.component_cost
    in
    if ptree.origin_cost = infinity then
        let adder = fun _ v acc -> (get_cost v) +. acc in
        All_sets.IntegerMap.fold adder ptree.component_root 0.
    else
        let adder = fun _ v acc -> (get_cost v) +. acc +. ptree.origin_cost in
        All_sets.IntegerMap.fold adder ptree.component_root (-. ptree.origin_cost)

let set_origin_cost cost ptree =
    { ptree with origin_cost = cost;}

let remove_root_of_component node ptree =
    { ptree with component_root =
        All_sets.IntegerMap.remove node ptree.component_root }

let empty data = {
    data = data;
    node_data = All_sets.IntegerMap.empty ;
    edge_data = Tree.EdgeMap.empty ;
    tree = Tree.empty ();
    component_root = All_sets.IntegerMap.empty;
    origin_cost = 0.;
}


type 'a clade_info = {
    clade_id: int;
    clade_node: 'a;
    topology_delta: Tree.side_delta;
}

type ('a, 'b) breakage = {
    ptree: ('a, 'b) p_tree;
    tree_delta: Tree.break_delta;
    break_delta: float;
    left: 'a clade_info;
    right: 'a clade_info;
    incremental : incremental list;
}


(* the nodes manager takes the properties from the cost, reroot, join, and break
 * functions, and determines how to iterate the tree *)
class type ['a, 'b] nodes_manager = object
    method update_iterate :
            ('a, 'b) p_tree -> 
            ([ `Break of ('a, 'b) breakage 
             | `Join of Tree.join_delta 
             | `Reroot of incremental list
             | `Cost ]) -> unit
    method clone : ('a, 'b) nodes_manager
    method branches : Tree.edge list option
    method model : bool
    method to_string : string
    method fuse : ('a,'b) nodes_manager -> ('a, 'b) nodes_manager
end

type ('a, 'b) break_fn =
    ('a, 'b ) nodes_manager option ->
        Tree.break_jxn -> ('a, 'b) p_tree -> ('a, 'b) breakage

type ('a, 'b) join_fn =   
    ('a, 'b ) nodes_manager option -> incremental list ->
        Tree.join_jxn -> Tree.join_jxn -> ('a, 'b) p_tree ->
            ('a, 'b) p_tree * Tree.join_delta

type ('a, 'b) model_fn =
    ?max_iter:int ->
        ('a, 'b ) nodes_manager option ->
            ('a, 'b) p_tree -> ('a, 'b) p_tree

(*type ('a, 'b) adjust_fn = *)
(*    ?max_iter:(int) ->*)
(*        ('a, 'b ) nodes_manager option ->*)
(*            ('a, 'b) p_tree -> ('a, 'b) p_tree*)

type ('a, 'b) cost_fn =
    ('a, 'b ) nodes_manager option -> Tree.join_jxn -> Tree.join_jxn ->
        float -> 'a -> ('a, 'b) p_tree -> clade_cost
    
type ('a, 'b) reroot_fn =
    ('a, 'b ) nodes_manager option -> bool -> Tree.edge ->
        ('a, 'b) p_tree -> ('a, 'b) p_tree * incremental list

type ('a, 'b) print_fn =
    string -> ('a, 'b) p_tree -> unit

module type Tree_Operations = 
    sig
        type a
        type b

        val break_fn : (a, b) break_fn
(*        val adjust_fn : (a, b) adjust_fn*)
        val model_fn : (a, b) model_fn
        val join_fn : (a, b) join_fn 
        val cost_fn : (a, b) cost_fn
        val reroot_fn : (a, b) reroot_fn
        val string_of_node : a -> string
        val features : 
            Methods.local_optimum -> (string * string) list -> 
                (string * string) list
        val clear_internals : bool -> (a, b) p_tree -> (a, b) p_tree
        val downpass : (a, b) p_tree -> (a, b) p_tree
        val uppass : (a, b) p_tree -> (a, b) p_tree
        val incremental_uppass : 
            (a, b) p_tree -> incremental list -> (a, b) p_tree

        val to_formatter :  
            Methods.diagnosis_report_type -> Xml.attributes -> (a, b) p_tree -> Xml.xml

        val branch_table : Methods.report_branch option -> (a,b) p_tree -> 
                ((int * int),[ `Name of (int array * float option) list | `Single of float ]) Hashtbl.t

        val root_costs : (a, b) p_tree -> (Tree.edge * float) list

        val total_cost : (a, b) p_tree -> [`Adjusted | `Unadjusted] -> int list option -> float

        val prior_cost : (a, b) p_tree -> int list option -> float
            
        val tree_size : (a, b) p_tree -> int list option -> float

        val unadjust : (a, b) p_tree -> (a, b) p_tree

        val refresh_all_edges : 
            a option -> bool -> (int * int) option -> (a,b) p_tree -> (a,b) p_tree

    end 


class type ['a, 'b] wagner_edges_mgr = object
    method break_distance : float -> unit
    method next_edge : Tree.edge option
    method next_clade : 'a -> unit
    method new_delta : float -> unit
    method update_join : ('a, 'b) p_tree -> Tree.join_delta -> unit
    method clone : ('a, 'b) wagner_edges_mgr
    method exclude : Tree.edge list -> unit
end

(** The tabu manager object that parameterizes the both the edges and the
* order in which the edges are visited by the searches. The invariant to be
* maintained by any tabu_mgr is that the edges in the tabu are always present in
* the tree. The directionality is flexible though. i.e. If the tree has edge(e1,
* e2) the tabu could have edge(e2, e1). *)
class type ['a, 'b] tabu_mgr = object

    method break_edge : Tree.edge option

    method break_distance : float -> unit

    method join_edge : [`Left | `Right] -> Tree.edge option

    method reroot_edge : [`Left | `Right] -> Tree.edge option

    method clone : ('a, 'b) tabu_mgr
    (** Function to create a deep-copy of the tabu. *)
    
    method update_break : ('a, 'b) breakage -> unit
    (** Function to update the tabu after a break operation. This function
       should ensure the invariant that edges in the tabu and the edges in the
       tree are in sync. Note that directionality could be reversed. *)

    method update_reroot  : ('a, 'b) breakage -> unit

    method update_join    : ('a, 'b) p_tree -> Tree.join_delta -> unit
        
    method get_node_manager : ('a, 'b) nodes_manager option

    method features : (string * string) list -> (string * string) list

    method break_edges : Tree.edge list
    
end 

class type ['a, 'b] wagner_mgr =
    object
        method any_trees : bool

        method clone : ('a, 'b) wagner_mgr

        method init :
            (('a, 'b) p_tree * float * clade_cost *
                ('a, 'b) wagner_edges_mgr) list -> unit

        method next_tree : ('a, 'b) p_tree * float * ('a, 'b) wagner_edges_mgr

        method process :
            ('a, 'b) cost_fn -> ('a, 'b) nodes_manager option -> float ->
                'a -> ('a, 'b) join_fn -> Tree.join_jxn -> Tree.join_jxn ->
                    ('a, 'b) p_tree -> ('a, 'b) wagner_edges_mgr -> t_status

        method evaluate : unit

        method results : (('a, 'b) p_tree * float) list
end

(** The search manager object that parameterizes the search. This
* allows us to incorporate various heuristics into the search easily. The
* parameterized types are the types from the p_tree. *)
  class type ['a, 'b] search_mgr = object
      method features : (string * string) list -> (string * string) list

      method init : 
          (('a, 'b) p_tree * float * clade_cost * ('a, 'b) tabu_mgr) list -> unit
      (** Function to initialize the list of trees to be searched
      * and their individual costs and break_deltas associated with
      * them. *)

      method clone : ('a, 'b) search_mgr
    (** Function to create a fresh instance of a search mgr object
        with all data initialized to default values. *)
          
    (** [process cost_fn join_fn
     *       join_1_jxn join_2_jxn tree_delta 
     *       broken_tree -> Travesal Status *)
      method process : 
        ('a, 'b) cost_fn -> float -> 'a -> ('a, 'b) join_fn -> incremental
            list -> Tree.join_jxn -> Tree.join_jxn -> ('a, 'b) tabu_mgr ->
                ('a, 'b) p_tree -> t_status
    (** This function decides whether to perform a join operation 
     * and add the tree to the queue of trees to be searched. *)
          
      method any_trees : bool 
    (** Function to return whether there are anymore trees to be
     * searched. *)
          
      method next_tree : (('a, 'b) p_tree * float * ('a, 'b) tabu_mgr)
    (** Function to return the next tree to be searched and its cost *)

      method results : (('a, 'b) p_tree * float * ('a, 'b) tabu_mgr) list
    (** Function to return the results of the search. *)

      method breakin : Tree.edge -> unit

      method should_repeat : bool

end 


module type SEARCH = 
    sig

        type a 
        type b

        val features : 
            Methods.local_optimum -> (string * string) list
                -> (string * string) list

        val recode : (a, b) p_tree -> int -> (a, b) p_tree

        val make_wagner_tree :
            ?sequence:(int list) -> (a, b) p_tree ->
                (a, b) nodes_manager option -> (a, b) wagner_mgr ->
                    ((a, b) p_tree -> int -> (a, b) wagner_edges_mgr) 
                -> (a, b) p_tree list

        val trees_considered : int ref

        type searcher = (a, b) search_mgr -> (a, b) search_mgr

        type search_step = 
            (a, b) p_tree -> (a, b) tabu_mgr -> searcher 

        (** [spr_step ptree tabu search] performs one round of SPR searching on
            tree [ptree] using a given tabu manager and search manager. *)
        val spr_step : search_step

        (** [spr_simple search] takes each tree in search manager [search] and
            performs rounds of SPR until there is no further improvement *)
        val spr_simple : bool -> searcher
      
        (** [tbr_step ptree tabu search] performs one round of TBR searching on
            tree [ptree] using a given tabu manager and search manager. *)
        val tbr_step : search_step

        (** [tbr_single search] performs one step of TBR on each tree in the
            search manager *)
        val tbr_single : searcher
        val spr_single : searcher

        (** [tbr_simple search] takes each tree in search manager [search] and
            performs rounds of TBR until there is no further improvement *)
        val tbr_simple : bool -> searcher

        val tbr_join :
          (a,b) tabu_mgr -> (a,b) search_mgr -> (a,b) breakage -> Tree.t_status

        (** [alternate_spr_tbr search] takes each tree in search manager [search]
            and performs rounds of alternating SPR and TBR until there is no further
             improvement *)
        val alternate : searcher -> searcher -> searcher

        val repeat_until_no_more : 
            ((a, b) p_tree -> (a, b) tabu_mgr) -> 
                searcher -> (a, b) search_mgr -> (a, b) search_mgr

        val get_trees_considered : unit -> int
        val reset_trees_considered : unit -> unit
        val uppass : (a, b) p_tree -> (a, b) p_tree
        val downpass : (a, b) p_tree -> (a, b) p_tree
        val diagnosis : (a, b) p_tree -> (a, b) p_tree

      (** [fuse_generations trees terminals max_trees tree_weight tree_keep iterations
          process] runs a genetic algorithm-style search using tree fusing.  The function
          takes a list of trees to start with, the number of terminals on each
          tree, the max number of trees and a method for
          keeping trees, a method for weighting trees, a number of iterations to perform,
          and a function to process new trees *)
        val fuse_generations :
            ((a, b) p_tree * (a,b) nodes_manager) list -> int -> int ->
                ((a, b) p_tree -> float) -> Methods.fusing_keep_method -> int ->
                    ((a, b) p_tree -> (a, b) p_tree list) -> (int * int)
                -> (a, b) p_tree list

        val search_local_next_best : (search_step * string) -> searcher

        val search : bool -> (search_step * string) -> searcher

        val convert_to :
            string option * Tree.Parse.tree_types list -> Data.d * a list 
                -> (a, b) p_tree

        val build_trees: 
            (* tree topology *) Tree.u_tree -> 
            (* gen names     *) (int -> string) -> 
            (* name subtrees *) (string -> int -> int -> (int array * float option) list -> string option) ->
            (* name tree     *) (Tree.u_tree -> int -> string) ->
            (* collapse node *) (int -> int -> bool) ->
            (* branch data   *) ((int * int), [ `Name of (int array * float option) list | `Single of float ]) Hashtbl.t option ->
            (* character sets*) int array option ->
            (* root data     *) (int array option -> string)
                -> (string option * Tree.Parse.tree_types) list

        val build_tree : 
            (* tree topology *) Tree.u_tree -> 
            (* gen names     *) (int -> string) -> 
            (* name subtrees *) (string -> int -> int -> (int array * float option) list -> string option) ->
            (* name tree     *) (Tree.u_tree -> int -> string) ->
            (* collapse node *) (int -> int -> bool) ->
            (* branch data   *) ((int * int), [ `Name of (int array * float option) list | `Single of float ]) Hashtbl.t option ->
            (* character sets*) int array option ->
            (* root data     *) (int array option -> string)
                -> (string option * Tree.Parse.tree_types)

        val get_collapse_function :
            Methods.report_branch option -> ((a, b) p_tree -> int -> int -> bool)
    
        val default_collapse_function : (a, b) p_tree -> int -> int -> bool

        val get_unique : (a, b) p_tree list -> (a, b) p_tree list 
        
        val get_unique_fn : ('a -> Tree.u_tree) -> ('a -> float) -> 'a list -> 'a list

        val build_tree_with_names :
            Methods.report_branch option -> (a, b) p_tree -> Tree.Parse.tree_types

        val build_tree_with_names_n_costs :
            Methods.report_branch option -> (a, b) p_tree -> string -> Tree.Parse.tree_types

        val build_forest :
            Methods.report_branch option -> (a, b) p_tree -> string -> Tree.Parse.tree_types list

        val build_forest_as_tree :
            Methods.report_branch option -> (a, b) p_tree -> string -> Tree.Parse.tree_types

        val build_forest_with_names :
            Methods.report_branch option -> (a, b) p_tree -> Tree.Parse.tree_types list

        val build_forest_with_names_n_costs :
            Methods.report_branch option -> (a, b) p_tree -> string -> bool * Methods.report_branch option ->
                int array option -> Tree.Parse.tree_types list

        val build_forest_with_names_n_costs_n_branches :
            Methods.report_branch option -> (a, b) p_tree -> string ->
                (string -> int -> int -> (int array * float option) list -> string option) ->
                    (Tree.u_tree -> int -> string) -> bool * Methods.report_branch option ->
                        int array option
                -> (string option * Tree.Parse.tree_types) list


        val to_xml : 
            Pervasives.out_channel -> (a, b) p_tree -> unit

        val disp_trees : 
            string ->
                (a, b) p_tree ->
                    ((a, b) p_tree -> int -> string)
                -> string -> unit
    end
    
(** The internal debug flag. *)
let debug = false
let debug_verify_costfn = false
let debug_verify_costfn_printnodes = false
let debug_verify_costfn_except_wagner = false
let debug_cost_print = true 
    
(** [int_of_id id]
    @param id is the id with associated type info `Node or `Handle.
    @return the int form of the id. See {!Tree.int_of_id} *)
let int_of_id = Tree.int_of_id

let handle_of id {tree=tree} = Tree.handle_of id tree

(** [get_id node]
    @return the id associated with the node. *)
let get_id = Tree.get_id 

(** [is_handle hnd ptree]
    @param hnd the handle id being verified.
    @param ptree the tree in which the id is either a handle or not. 
    @return true if the id corresponds to a handle. false, otherwise. *)
let is_handle hnd ptree =
    (Tree.is_handle hnd ptree.tree)

(** [is_edge (x,y) ptree]
    @param (x,y) the tuple that corresponds to an edge or not.
    @param ptree the tree in which the tuple, corresponds to an edge or not.
    @return true if the tuple corresponds to an edge, false if otherwise. *)
let is_edge e ptree = 
    (Tree.is_edge e ptree.tree)

(** [get_node_id id ptree]
    @param id the int whose id form is desired. id form tacks on a `Node
              to the integer.
    @param ptree the tree in which the int represents a node. 
    @raise Tree.Invalid_Node_Id
    @return The id form or throws an exception if the node is invalid. *)
let get_node_id id ptree = 
    (Tree.get_node_id id ptree.tree)

(** [get_handle_id id ptree]
    @param id the int whose id form is desired. id form tacks on a `Handle
              to the integer.
    @param ptree the tree in which the int represents a handle. 
    @raise Tree.Invalid_Handle_Id
    @return the handle form of the id. *)
let get_handle_id id ptree = 
    (Tree.get_handle_id id ptree.tree)
   
(** [get_handles ptree]
    @return the handle set of the tree. *)
let get_handles ptree = 
    (Tree.get_handles ptree.tree)

(** [components forest] returns the number of components in the forest *)
let components forest =
    All_sets.Integers.cardinal (get_handles forest)


(** [get_node id ptree]
    @param id the int-id of the the node.
    @param ptree the tree from which the node of the given id is being
                retrieved.
    @return the node associated with the given id.
    @raise Tree.Invalid_Node_Id when the id is invalid. *)
let get_node id ptree =
    (Tree.get_node id ptree.tree)

(** [get_edge (x, y) ptree]
    @param (x, y) the pair that could correspond to an edge in the tree.
    @param ptree the tree from which the edge is being retrieved.
    @return the edge corresponding to the pair.
    @raise Tree.Invalid_Edge if the pair doesnt correspond to an edge. *)
let get_edge (x, y) ptree = 
    (Tree.get_edge (x, y) ptree.tree)

(** [get_parent id ptree]
    @param id the id of the node whose parent is desired. Parent is the node
    that would be visited immediately before the present node in a
    pre-order-traversal from the handle of the component to which the node
    belongs. An exception is thrown when the id corresponds to a handle.
    @param ptree the tree in which the parent of node with id=id is determined.
    @return the parent of the node if it exists, otherwise an exception is
    thrown. *)
let get_parent id ptree = 
    (Tree.get_parent id ptree.tree)

(** [other_two_nbrs nbr node]
    @param nbr a nbr of the node
    @param node the interior node whose other two nbrs are desired.
    @return the other two nbrs of the node. 
    @raise Invalid_argument if the node is not an interior node. *)
let other_two_nbrs = Tree.other_two_nbrs
    
(** [get_nodes ptree]
    @return the list of all the nodes of the tree. *)
let get_nodes ptree = 
    (Tree.get_nodes ptree.tree)
   
(** [get_pre_order_edges hs ptree]
    @return the list of edges when visiting the tree in a pre-order
            traversal starting at the handle hs. *)
let get_pre_order_edges hs ptree = 
    (Tree.get_pre_order_edges hs ptree.tree)
    
let get_edges_tree ptree = 
    (Tree.get_edges_tree ptree.tree)
    
(** [get_node_ids ptree]
    @return the list of all node ids of the tree. *)
let get_node_ids ptree = 
    (Tree.get_node_ids ptree.tree)

(** [add_node_data id data ptree]
    @param id to which node data is added.
    @param data being added to the node
    @param ptree to which node data is being added. 
    @return new ptree with the data added to node with id=id.
            Any old data is silently overwritten. *)
let add_node_data id data ptree = 
    let debug = false in
    if debug then begin
        Printf.printf "ptree.add_node_data to Node:%d\n%!" id;
    end;
    let new_node_data = (All_sets.IntegerMap.add id data ptree.node_data) in
        { ptree with node_data = new_node_data }

(** [add_edge_data edge data ptree]
    @param edge to which data is being added.
    @param data being added to the edge.
    @param ptree to which the edge data is being added.
    @return new ptree with the edge data added. Any old data
            will be silently overwritten. *)
let add_edge_data edge data ptree = 
    let edge = Tree.normalize_edge edge ptree.tree in 
    let new_edge_data = (Tree.EdgeMap.add edge data ptree.edge_data) in
        { ptree with edge_data = new_edge_data }

(** [remove_node_data id ptree]
    @return a new ptree with data associated with node_id=id erased. *)
let remove_node_data id ptree =
    let new_node_data = (All_sets.IntegerMap.remove id ptree.node_data) in
        { ptree with node_data = new_node_data }

let print_node_data_keys ptree =
    Printf.printf "these node data are in ptree: [";
    All_sets.IntegerMap.iter (fun key item -> Printf.printf "%d," key)
    ptree.node_data;
    Printf.printf "]\n%!"


(** [remove_edge_data edge ptree]
    @return a new ptree with data associated with edge removed. *)
let remove_edge_data edge ptree = 
    let edge = Tree.normalize_edge edge ptree.tree in
    let new_edge_data = (Tree.EdgeMap.remove edge ptree.edge_data) in
        { ptree with edge_data = new_edge_data }

(** [get_node_data id ptree]
    @return data associated with the node. *)
let get_node_data id ptree =
    (All_sets.IntegerMap.find id ptree.node_data)

(** [get_parent_or_root_data id ptree] returns the data of the node's "literal"
    parent if the node is in the tree, or returns the root data if the root is
    the node's real edge *)
let get_parent_or_root_data id ptree =
    let get_root parent =
        match
            (All_sets.IntegerMap.find parent
                 ptree.component_root).root_median
        with
        | None -> failwith "get_parent_or_root_data"
        | Some (_, data) -> data in
    if is_handle id ptree
    then get_root id
    else
        let parent = get_parent id ptree in
        if is_handle parent ptree
        then
            match get_node parent ptree with
            | Tree.Leaf (_, par) when par = id ->
                  get_root parent
            | Tree.Interior (_, par, _, _) when par = id ->
                  get_root parent
            | _ -> get_node_data parent ptree
        else get_node_data parent ptree
    
(** [get_edge_data edge ptree]
    @return data associated with the edge. *)
let get_edge_data edge ptree = 
    try (Tree.EdgeMap.find edge ptree.edge_data) with
    | Not_found -> 
            let Tree.Edge (a, b) = edge in
            Tree.EdgeMap.find (Tree.Edge (b, a)) ptree.edge_data
   
let move_cost_n_root hid id ptree =
    let comp_cost = ptree.component_root in
    try let x = All_sets.IntegerMap.find hid comp_cost in
        let res = All_sets.IntegerMap.remove hid comp_cost in
        let res = All_sets.IntegerMap.add id { x with root_median = None } res in
        { ptree with component_root = res }
    with | Not_found -> ptree

(** [move_handle id ptree]
    @return new ptree with the current id as a handle. THE DATA
    ASSOCIATED WITH edges Edge(e2, e1) IS NOT UPDATED. *)
let move_handle id ptree = 
    let hid, _ = Tree.get_path_to_handle id ptree.tree in
    let bt, path = (Tree.move_handle id ptree.tree) in
    move_cost_n_root hid id { ptree with tree = bt }, path

let fix_handle_neighbor h n ptree =
    { ptree with tree = Tree.fix_handle_neighbor h n ptree.tree }

(** [pre_order_node_visit f id ptree acc]
    Function to perform a pre order node visit on the tree.
    See {!Tree.pre_order_node_visit} *)
let pre_order_node_visit f id ptree acc = 
    Tree.pre_order_node_visit f id ptree.tree acc 

(** [post_order_node_visit f id ptree acc]
    Function to perform a post order node visit on the tree.
    See {!Tree.post_order_node_visit} *)
let post_order_node_visit f id ptree acc = 
    Tree.post_order_node_visit f id ptree.tree acc 

(** [post_order_node_with_edge_visit]
    @return What does this function do? *)
let post_order_node_with_edge_visit f g e ptree acc = 
    Tree.post_order_node_with_edge_visit f g e ptree.tree acc
    
(** [pre_order_edge_visit f id ptree acc]
    Function to perform a pre order edge visit on the tree.
    See {!Tree.pre_order_edge_visit} *)
let pre_order_edge_visit f id ptree acc = 
    Tree.pre_order_edge_visit f id ptree.tree acc

(** [create_partitions t l r]
    Create partition of node ids from edge l--r *)
let create_partition t e = 
    Tree.create_partition t.tree e

let robinson_foulds t1 t2 =
    Tree.robinson_foulds t1.tree t2.tree

let post_order_downpass_style leaf interior id ptree =
    let rec processor prev curr =
        match get_node curr ptree with
        | Tree.Single _ -> assert false
        | Tree.Leaf _ -> leaf (Some prev) curr 
        | (Tree.Interior _) as node ->
                let a, b = other_two_nbrs prev node in
                let a = processor curr a
                and b = processor curr b in
                interior (Some prev) (Some curr) a b
    in
    let root = 
        All_sets.IntegerMap.find id ptree.component_root 
    in
    match root.root_median with
    | None -> failwith "Root required"
    | Some ((`Single x), _) -> leaf None x
    | Some (`Edge (a, b), _) ->
            let a = processor b a 
            and b = processor a b in
            interior None None a b
    
(** [print_tree hnd ptree]
    Function to print a tree rooted at the given handle *)
let print_tree hnd ptree = 
    Tree.print_tree hnd ptree.tree
    
(** [print_forest ptree]
    Function to print the entire forest. *)
let print_forest ptree = 
    Tree.print_forest ptree.tree


(** [make_disjoint_tree n leaf_data_map]
    @param n the number of leaves.
    @param leaf_data_map a map from {1, 2, ... n} to the leaf data.
    @return the disjointed tree with n nodes. 0 edges and data
            associated with the nodes. *)
let make_disjoint_tree data leaf_data_map = 
    let f k d acc = k :: acc in
    let nodes = (All_sets.IntegerMap.fold f leaf_data_map []) in
    let bt = Tree.make_disjoint_tree nodes in
        { (empty data) with tree = bt ; node_data = leaf_data_map }

let get_component_root handle ptree = 
    All_sets.IntegerMap.find handle ptree.component_root

let get_component_root_median handle ptree = 
    match (get_component_root handle ptree).root_median with
    | None -> failwith "No root assigned"
    | Some (_, x) -> x

let get_roots ptree =
    All_sets.Integers.fold (fun x acc -> (get_component_root x ptree) :: acc) 
    ptree.tree.Tree.handles []

let change_component_root handle root ptree = 
    let com_root = All_sets.IntegerMap.add handle root ptree.component_root in
    {ptree with component_root = com_root}


let choose_leaf tree = 
    match 
    All_sets.IntegerMap.fold (fun x n acc -> match n with Tree.Leaf _ -> Some x | _
    -> acc) tree.tree.Tree.u_topo None
    with
    | Some v -> v
    | None -> failwith "A tree with no leafs?"


let empty_name_subtree _ _ _ = None

let basic_tree_name t = match t.tree.Tree.tree_name with
    | Some x -> x
    | None   -> ""

(** [build_trees tree]
    @param tree the ptree which is being converted into a Tree.Parse.t
    @param str_gen is a function that generates a string for each vertex in the tree
    @param collapse is a function that check if a branch can be collapsed.
    @return the ptree in the form of a Tree.Parse.t *)
let build_trees tree str_gen name_subtree name_tree collapse branches chars root_fn =
    let sortthem a b ao bo data ad bd = match String.compare ao bo with
        | 0 | 1 -> Tree.Parse.Nodep (b @ a, data), bd + 1, bo
        | _ -> Tree.Parse.Nodep (a @ b, data), bd + 1, ao
    and get_children = function
        | Tree.Parse.Leafp _ as x -> [x]
        | Tree.Parse.Nodep (lst, _) -> lst
    (* return the characters contained in this tree and the unwrapped branches *)
    and branches = match branches with
        | None   -> Hashtbl.create 1
        | Some x -> x
    (* a single element is taken to represent the entire set *)
    and char = match chars with
        | None   -> None
        | Some x -> Some x.(0)
    in
    let str_gen tree_name is_root id parent_option =
        let rec find_assoc char data =
            let rec find_array i xs =
                if i = Array.length xs then false
                else if xs.(i) = char then true
                else find_array (i+1) xs
            in
            match data with
            | (xs,d)::_ when find_array 0 xs -> d
            | _::xs -> find_assoc char xs
            | []    -> raise Not_found
        in
        let labels =
            try begin match parent_option with
            | None -> raise Not_found
            | Some par ->
                let (x,y) as pair = min id par,max id par in
                begin match Hashtbl.find branches pair, char with
                | `Single length, _ ->
                    let bl = if is_root then length /. 2.0 else length in
                    Some bl, None
                | `Name data, None ->
                    let name = name_subtree tree_name x y data in
                    None, name
                | `Name data, Some char ->
                    begin match find_assoc char data with
                    | Some length ->
                        let bl = if is_root then length /. 2.0 else length in
                        Some bl, None
                    | None ->
                        let name = name_subtree tree_name x y data in
                        None, name
                    end
                end
            end with
            | Not_found -> None, None
        and data =
            try str_gen id with | Not_found -> "" 
        in
        data,labels
    in
    let rec rec_down tree_name is_root node prev_node = match node with
        | Tree.Leaf (self, parent) -> 
              let data = str_gen tree_name is_root self (Some parent) in
              Tree.Parse.Leafp data, 0, (fst data)
        | Tree.Interior (our_id, _, _, _) ->
              let (ch1, ch2) = 
                  assert (prev_node <> Tree.get_id node);
                  Tree.other_two_nbrs prev_node node
              in
              (* process subtrees *)
              let a, ad, ao = rec_down tree_name false (Tree.get_node ch1 tree) our_id in
              let b, bd, bo = rec_down tree_name false (Tree.get_node ch2 tree) our_id in
              (* collapse branches *)
              let a = if collapse our_id ch1 then get_children a else [a]
              and b = if collapse our_id ch2 then get_children b else [b] in
              (* deal with this node *)
              let data = str_gen tree_name is_root our_id (Some prev_node) in
              if bd > ad then
                  Tree.Parse.Nodep (a @ b, data), bd + 1, bo
              else if bd = ad then
                  sortthem a b ao bo data ad bd 
              else 
                  Tree.Parse.Nodep (b @ a, data), ad + 1, ao
        | Tree.Single _ -> failwith "Unexpected single"
    in
    let single_tree acc handle : (string option * Tree.Parse.tree_types) list =
        let tree_name = name_tree tree handle in
        let tree = match Tree.get_node handle tree with
            | Tree.Leaf (self, parent) ->
               let acc,_,_ = rec_down tree_name true (Tree.get_node parent tree) handle in
               let str = str_gen tree_name true self (Some parent) in 
               [(Tree.Parse.Leafp str); acc]
            | Tree.Interior (self, par_id, ch1, ch2) ->
               let par = Tree.get_node par_id tree in
               let ch1 = Tree.get_node ch1 tree in
               let ch2 = Tree.get_node ch2 tree in
               let acc, accd, acco = rec_down tree_name true par handle in
               let acc1, acc1d, acc1o = rec_down tree_name false ch1 handle in
               let acc2, acc2d, acc2o = rec_down tree_name false ch2 handle in
               let data = str_gen tree_name true self (Some par_id) in
               if acc2d > acc1d then
                   if acc1d > accd then
                       [Tree.Parse.Nodep ([acc; acc1], data); acc2]
                   else 
                       [Tree.Parse.Nodep ([acc1; acc], data); acc2]
               else if acc1d > accd then
                   if acc2d > accd then 
                       [Tree.Parse.Nodep ([acc; acc2], data); acc1]
                   else 
                       [Tree.Parse.Nodep ([acc2; acc], data); acc1]
               else 
                   if acc2d > acc1d then
                       [Tree.Parse.Nodep ([acc1;acc2], data); acc]
                   else
                       [Tree.Parse.Nodep ([acc2;acc1], data); acc]
            | Tree.Single self ->
                [(Tree.Parse.Leafp (str_gen tree_name true self None))]
        in
        let tree  = Tree.Parse.Nodep (tree,("",(None,None)))
        and annot = root_fn chars in
        ((Some tree_name, Tree.Parse.post_process (tree,annot))) :: acc
    in
    List.fold_left single_tree [] (All_sets.Integers.elements (Tree.get_handles tree))


(** Functor to allow for SPR/TBR searches over phylogenetics trees of 
    different types of characters. *)
module Search (Node : NodeSig.S) (Edge : Edge.EdgeSig with type n = Node.n) 
              (Tree_Ops : Tree_Operations with type a = Node.n with type b = Edge.e) =
  struct

    type a = Tree_Ops.a
    type b = Tree_Ops.b

    let features meth lst = Tree_Ops.features meth lst

    let downpass    = Tree_Ops.downpass
    let uppass      = Tree_Ops.uppass
    let diagnosis x = uppass (downpass x)

    let all_edges_represented ptree =
        (Tree.EdgeSet.fold (fun key acc ->
            let Tree.Edge (a, b) = key in
            let res = Tree.EdgeMap.mem key ptree.edge_data || 
                Tree.EdgeMap.mem (Tree.Edge (b, a)) ptree.edge_data in
            if not res then begin
                Printf.printf "Edge Data doesn't exist: %d, %d\n%!" a b;
            end;
            acc && res)
            ptree.tree.Tree.d_edges true) &&
        (Tree.EdgeMap.fold (fun key _ acc ->
            let key = 
                try Tree.normalize_edge key ptree.tree with
                | _ -> key
            in
            let res = Tree.EdgeSet.mem key ptree.tree.Tree.d_edges in
            if not res then begin
                let Tree.Edge (a, b) = key in
                Printf.printf "Edge doesnt exist: %d, %d\n%!" a b;
            end;
            acc && res) 
            ptree.edge_data true)

    let edge_recode ptree (Tree.Edge (a, b)) starting =
        let hash = Hashtbl.create 97 in
        let find x = 
            try Hashtbl.find hash x with 
            | Not_found -> 
                    Hashtbl.add hash x x;
                    x 
        in
        let recode_tree_data tree =
            let node_data = 
                All_sets.IntegerMap.fold (fun key node acc ->
                    All_sets.IntegerMap.add (find key)
                    (Node.recode find node) acc)
                tree.node_data
                All_sets.IntegerMap.empty
            and edge_data =
                Tree.EdgeMap.fold (fun (Tree.Edge (a, b)) e acc ->
                    Tree.EdgeMap.add 
                    (Tree.Edge ((find a), (find b)))
                    (Edge.recode find e)
                    acc)
                tree.edge_data
                Tree.EdgeMap.empty
            and component_root =
                All_sets.IntegerMap.fold (fun key root acc ->
                    All_sets.IntegerMap.add 
                    (find key)
                    { root with root_median = 
                        match root.root_median with
                        | None -> None
                        | Some ((`Edge (a, b)), n) ->
                                Some ((`Edge (find a, find b)), Node.recode find
                                n)
                        | Some ((`Single a), n) ->
                                root.root_median } acc)
                tree.component_root
                All_sets.IntegerMap.empty
            in
            { tree with 
                node_data = node_data;
                edge_data = edge_data;
                component_root = component_root; }
        in
        let get_parent parent b =
            match parent with
            | None -> (Some b)
            | Some x -> (Some x)
        in
        let rec process_recode parent (a, b) code acc =
            let ac = 
                let ad = get_node_data a ptree in
                Node.min_child_code (get_parent parent b) ad 
            and bc = 
                let bd = get_node_data b ptree in
                Node.min_child_code (get_parent parent a) bd 
            in
            let a, b, ac, bc =
                if ac < bc then a, b, ac, bc
                else b, a, bc, ac
            in
            let code, acc =
                if Tree.is_leaf a ptree.tree then code, acc
                else recursive_call a (get_parent parent b) code acc
            in
            let code, acc =
                if Tree.is_leaf b ptree.tree then code, acc
                else recursive_call b (get_parent parent a) code acc
            in
            match parent with
            | None -> 
                    code + 1, acc
            | Some x -> 
                    let new_code = find code 
                    and new_x = find x in
                    let acc = 
                        { acc with tree = 
                            Tree.exchange_codes new_x new_code acc.tree }
                    in
                    Hashtbl.replace hash code new_x;
                    Hashtbl.replace hash x new_code;
                    code + 1, acc
        and recursive_call node parent code acc =
            match parent with
            | Some x ->
                    let a, b = 
                        Tree.other_two_nbrs x (Tree.get_node node ptree.tree)
                    in
                    process_recode (Some node) (a, b) code acc
            | None -> assert false
        in
        let code, tree = process_recode None (a, b) starting ptree in
        let tree = recode_tree_data tree in
        hash, code, tree

    let recode ptree code = 
        let _, ptree = 
            List.fold_left (fun (code, ptree) handle ->
            match handle.root_median with
            | None -> (code, ptree)
            | Some ((`Single _), _) -> (code, ptree)
            | Some ((`Edge (a, b)), _) ->
                    let _, a, b = edge_recode ptree (Tree.Edge (a, b)) code in
                    a, b) (code, ptree)
                    (get_roots ptree)
        in 
        ptree


    (** Function used for debugging purposes...*)
    let verify_cost old_cost old_delta cdnd new_delta j1 j2 t_delta pt =
        let t, _ = Tree_Ops.join_fn None [] j1 j2 pt in
        let new_cost = get_cost `Adjusted t in
        match new_delta with
        | Cost new_delta ->
              let supposed_new_cost = old_cost -. old_delta +. new_delta in
              if supposed_new_cost <> new_cost
              then begin
                  if new_cost > supposed_new_cost
                  then print_endline ("cost_fn optimistic: "
                                      ^ string_of_float
                                      (new_cost -. supposed_new_cost)
                                      ^ " (delta reported was " ^
                                      string_of_float new_delta ^ ")")
                  else print_endline ("cost_fn pessimistic: "
                                      ^ string_of_float
                                      (supposed_new_cost -. new_cost));
                  if debug_verify_costfn_printnodes
                  then begin
                      let clade_node = get_node_data cdnd pt in
                      print_endline ("clade node: "
                                     ^ Tree_Ops.string_of_node clade_node);
                      begin
                          match j1 with
                          | Tree.Single_Jxn h ->
                                print_endline ("trying to join at "
                                               ^ Tree_Ops.string_of_node
                                               (get_node_data
                                                    (Tree.int_of_id h) pt))
                          | Tree.Edge_Jxn (n1, n2) ->
                                print_endline ("trying to join at "
                                               ^ Tree_Ops.string_of_node
                                               (get_node_data
                                                    (Tree.int_of_id n1) pt));
                                print_endline ("              and "
                                               ^ Tree_Ops.string_of_node
                                               (get_node_data
                                                    (Tree.int_of_id n2) pt))
                      end
                  end
              end
        | NoCost ->
              (* Just check that the actual delta > old delta *)
              if new_cost < old_cost
              then print_endline ("..cost_fn skips incorrectly!")
        
      class mymgr ptree : [Tree_Ops.a, Tree_Ops.b] wagner_mgr = object
          method any_trees = false
          method clone = ({<>} :> (Tree_Ops.a, Tree_Ops.b) wagner_mgr)
          method init _ = ()
          method next_tree = assert false
          method process _ _ _ _ _ _ _ _ _ = assert false
          method evaluate = ()
          method results = [ptree, get_cost `Adjusted ptree]
      end


    let best_of_list lst compare =
        let rec until x acc = function
            | y::ys when 0 = compare x y -> until x (y::acc) ys
            | _ -> acc
        in
        match lst with
        | [] -> []
        | xs -> let y = List.sort compare lst in
                let x = List.hd y in
                until x [x] y

    (** [make_wagner_tree ptree join_fn cost_fn]
        @param ptree The initial ptree that is just a bunch of single nodes
                     with node data associated.
        @param join_fn function used to join the nodes to build the wagner 
                       tree.
        @param cost_fn function to determine the cost of the tree.
        @return the wagner tree. i.e. best spr tree over the given data. *)
    let make_wagner_tree ?(sequence) ptree
            (i_mgr    : (Tree_Ops.a, Tree_Ops.b) nodes_manager option)
            (srch_mgr : (Tree_Ops.a, Tree_Ops.b) wagner_mgr)
            (create_tabu_mgr : (('a, b) p_tree -> int -> (Tree_Ops.a, Tree_Ops.b) wagner_edges_mgr)) =
        let nodes = match sequence with
            | None   -> Tree.handle_list ptree.tree
            | Some r -> List.map (fun x -> handle_of x ptree) r
        in
        (* make sure you have atleast two nodes to build a tree
           (one edge only) of type a -- b *)
        let res = match nodes with
            | n1 :: n2 :: rest ->
                let status = Status.create "Wagner" (Some (2 + List.length rest)) "" in
                (* build one edge tree with h1 h2 *)
                let h1 = Tree.get_handle_id n1 ptree.tree
                and h2 = Tree.get_handle_id n2 ptree.tree in
                let j1, j2 =
                    let get_corrected_jnx nd = match get_node nd ptree with
                        | Tree.Single _ -> Tree.Single_Jxn nd
                        | Tree.Leaf (x, y)
                        | Tree.Interior (x, y, _, _) -> Tree.Edge_Jxn (x, y)
                    in
                    (get_corrected_jnx h1), (get_corrected_jnx h2)
                in
                let ptree, tree_delta = (Tree_Ops.join_fn i_mgr [] j1 j2 ptree) in
                (* Now we ensure that the root is located in between the two 
                   handles that we just joined. This is needed for constrained
                   building. *)
                let ptree  = 
                    let l, r, _ = tree_delta in
                    let new_vertex x = match x with
                        | `Single (x, _)
                        | `Edge (x, _, _, _) -> x
                    in
                    let l = new_vertex l and r = new_vertex r in
                    let tree, inc =
                        Tree_Ops.reroot_fn i_mgr true (Tree.Edge (l, r)) ptree
                    in
                    Tree_Ops.incremental_uppass tree inc
                in
                let cst = get_cost `Adjusted ptree in
                (* function adds the given nd to each of the edges of pt and
                   picks the tree/s according to some optimality criterion. *)
                let add_node_everywhere (pt, cst, tabu_mgr) nd srch_mgr =
                    let j2, nd_data =
                        match (get_component_root nd ptree).root_median with
                        | None -> assert false
                        | Some ((`Edge (x, y)), z) -> (Tree.Edge_Jxn (x, y)), z
                        | Some ((`Single x), z) -> (Tree.Single_Jxn x), z
                    in
                    tabu_mgr#next_clade nd_data;
                    (* function to add a node to an edge and determine the
                       optimality of the resulting tree. *)
                    let add_node_to_edge e srch_mgr tabu_mgr = 
                        let Tree.Edge(e1, e2) = e in
                        let h1 = (Tree.get_node_id e1 pt.tree)
                        and h2 = (Tree.get_node_id e2 pt.tree) in
                        let j1 = Tree.Edge_Jxn(h1, h2) in
                        let status:t_status =
                            srch_mgr#process Tree_Ops.cost_fn i_mgr infinity
                                    nd_data Tree_Ops.join_fn j1 j2 pt tabu_mgr
                        in 
                        status, srch_mgr
                    in
                    (* Sequentially add rest of the nodes keeping the best tree/s *)
                    let srch_mgr = 
                        (* recursive/sequential version to find costs and join
                            all edges *)
                        let rec do_all_edges srch_mgr tabu_mgr =
                            match tabu_mgr#next_edge with
                                | None -> srch_mgr
                                | Some e ->
                                    let _, mgr = add_node_to_edge e srch_mgr tabu_mgr in
                                    do_all_edges mgr tabu_mgr
                        in
                    IFDEF USE_PARMAP THEN
                        (* parallel determine all costs, then fold to select
                            best and do a proper join. *)
                        let par_do_all_edges srch_mgr tabu_mgr =
                            let rec get_edges acc = match tabu_mgr#next_edge with
                                | None   -> acc
                                | Some (Tree.Edge (e1,e2)) ->
                                    let h1 = (Tree.get_node_id e1 pt.tree)
                                    and h2 = (Tree.get_node_id e2 pt.tree) in
                                    let j1 = Tree.Edge_Jxn(h1, h2) in
                                    get_edges (j1::acc)
                            in
                            match get_edges [] with
                            | [] -> srch_mgr
                            | xs ->
                                let costs : (Tree.join_jxn * clade_cost) list =
                                    Parmap.parmap
                                        (fun j1 ->
                                            let cst =
                                                Tree_Ops.cost_fn None j1
                                                    j2 infinity nd_data pt in
                                            (j1,cst))
                                        (Parmap.L xs)
                                in
                                let besties =
                                    best_of_list costs (fun (_,x) (_,y) -> compare_clade_cost x y)
                                in
                                List.fold_left
                                    (fun srch_mgr (j1,cost) ->
                                        let status : t_status =
                                            srch_mgr#process
                                                (fun _ _ _ _ _ _ -> cost) i_mgr infinity
                                                nd_data Tree_Ops.join_fn j1 j2 pt tabu_mgr
                                        in
                                        srch_mgr)
                                    srch_mgr
                                    besties
                        in
                        if 1 = Parmap.get_default_ncores ()
                            then do_all_edges srch_mgr tabu_mgr
                            else par_do_all_edges srch_mgr tabu_mgr
                    ELSE
                        do_all_edges srch_mgr tabu_mgr
                    END
                    in
                    (* There has to be at least one new tree *)
                    assert(srch_mgr#any_trees);
                    () 
                in
                (* sequentially add rest of the nodes to the tree *)
                let rec seq_add nodes srch_mgr added = match nodes with
                    | []       -> srch_mgr
                    | nd::rest ->
                        let n_srch_mgr = (srch_mgr#clone) in
                        assert(n_srch_mgr#any_trees = false);
                        while srch_mgr#any_trees do 
                            let (_, cst, _) as it = srch_mgr#next_tree in
                            Status.full_report ~msg:("Wagner tree with cost "^string_of_float cst)
                                               ~adv:(added) status;
                            add_node_everywhere it nd n_srch_mgr;
                            n_srch_mgr#evaluate;
                        done;
                        seq_add rest n_srch_mgr (added+1)
                in
                let tabu_mgr = create_tabu_mgr ptree h1 in
                srch_mgr#init [(ptree, cst, Cost(infinity), tabu_mgr)];
                let result = (seq_add rest srch_mgr 2) in
                Status.finished status;
                result
            (* need at least two nodes *)
            | _ -> new mymgr ptree
        in
        List.map fst (res#results)


let trees_considered = ref 0


let fix_edge ptree ((Tree.Edge (e1, e2)) as edge) =
    (* if the edge is in tree, return the edge. *)
    if (is_edge edge ptree) then
        edge
    (* otherwise, check whether the reversed-edge is in the tree. *)
    else if (is_edge (Tree.Edge (e2, e1)) ptree) then
        Tree.Edge(e2, e1) 
    (* neither the edge nor its reverse was found in tree i.e. tabu and
       tree are out of sync. *)
    else failwith "fix_edge"


type searcher =
        (Tree_Ops.a, Tree_Ops.b) search_mgr ->
            (Tree_Ops.a, Tree_Ops.b) search_mgr


type search_step = 
        (Tree_Ops.a, Tree_Ops.b) p_tree ->
            (Tree_Ops.a, Tree_Ops.b) tabu_mgr ->
                searcher


let other_side = function `Left -> `Right | `Right -> `Left


let get_side_info side break = match side with
    | `Left -> break.left
    | `Right -> break.right


let apply_incremental breakage =
    let ptree = Tree_Ops.incremental_uppass breakage.ptree breakage.incremental in
    { breakage with ptree = ptree; incremental = [] }


let simplify x jxn = 
    let compare x y = match x, y with
        | `Single (x, _), Tree.Single_Jxn y -> x = y
        | `Edge (_, l1, l2, _), Tree.Edge_Jxn (a, b) ->
                (a = l1 && b = l2) || (b = l1 && a = l2)
        | _ -> false
    in
    match x with
    | `Pair (x, y) -> 
            if compare x jxn then `Single y
            else if compare y jxn then `Single x
            else `Pair (x, y)
    | `Single y -> if compare y jxn then `Same else x
    | `Same -> assert false

IFDEF USE_PARMAP THEN
let par_single_spr_round pb parent_side child_side
        (tabu : (Tree_Ops.a, Tree_Ops.b) tabu_mgr) (search : (Tree_Ops.a, Tree_Ops.b) search_mgr) breakage =
    let child_info = get_side_info child_side breakage in
    let child_jxn, handle_of_child = match child_info.topology_delta with
        | `Single (a, _) -> 
                Tree.Single_Jxn a, handle_of a breakage.ptree
        | `Edge (_, a, b, _) -> 
                assert (handle_of a breakage.ptree = handle_of b breakage.ptree);
                Tree.Edge_Jxn (a, b), handle_of a breakage.ptree
    in
    let npb = simplify pb child_jxn in
    let simplifier = match npb with
        | `Pair _ -> fun x _ -> x
        | `Single _ -> simplify
        | `Same -> assert false
    in
    let rec get_edges acc = match tabu#join_edge parent_side with
        | None -> acc
        | Some (Tree.Edge (a,b)) ->
            let parent_jxn = (Tree.Edge_Jxn (a, b)) in
            begin match simplifier npb parent_jxn with
                | `Same -> get_edges acc
                | _     -> get_edges (parent_jxn::acc)
            end
    in
    match get_edges [] with
    | [] -> Tree.Continue
    | xs ->
        let costs =
            Parmap.parmap
                (fun parent_jxn ->
                    let cst =
                        Tree_Ops.cost_fn None parent_jxn child_jxn
                            breakage.break_delta child_info.clade_node breakage.ptree
                    in
                    parent_jxn,cst)
                (Parmap.L xs)
        in
        let besties =
            best_of_list costs (fun (_,x) (_,y) -> compare_clade_cost x y)
        in
        let status : t_status =
            List.fold_left
                (fun _ (parent_jxn,cost) ->
                    search#process
                        (fun _ _ _ _ _ _ -> cost) breakage.break_delta
                        child_info.clade_node Tree_Ops.join_fn breakage.incremental
                        parent_jxn child_jxn tabu breakage.ptree)
                Tree.Continue
                besties
        in
        Tree.Continue
END

let single_spr_round pb parent_side child_side 
        (tabu : (Tree_Ops.a, Tree_Ops.b) tabu_mgr) (search : (Tree_Ops.a, Tree_Ops.b) search_mgr) breakage =
    let child_info = get_side_info child_side breakage in
    let child_jxn, handle_of_child = match child_info.topology_delta with
        | `Single (a, _) -> 
                Tree.Single_Jxn a, handle_of a breakage.ptree
        | `Edge (_, a, b, _) -> 
                assert (handle_of a breakage.ptree = handle_of b breakage.ptree);
                Tree.Edge_Jxn (a, b), handle_of a breakage.ptree
    in
    let npb = simplify pb child_jxn in
    let simplifier = match npb with
        | `Pair _ -> fun x _ -> x
        | `Single _ -> simplify
        | `Same -> assert false
    in
    let rec do_search () = match tabu#join_edge parent_side with
        | None -> Tree.Continue
        | Some (Tree.Edge (a, b)) ->
            let parent_jxn = (Tree.Edge_Jxn (a, b)) in
            match simplifier npb parent_jxn with
            | `Same -> do_search ()
            | _ ->
                let what_to_do_next =
                    search#process Tree_Ops.cost_fn breakage.break_delta 
                        child_info.clade_node Tree_Ops.join_fn
                        breakage.incremental parent_jxn child_jxn tabu breakage.ptree
                in
                match what_to_do_next with
                | Tree.Skip
                | Tree.Continue -> do_search ()
                | x -> x
    in
    do_search ()

let single_spr_round a b c d e f =
    IFDEF USE_PARMAP THEN
        if 1 = Parmap.get_default_ncores ()
            then     single_spr_round a b c d e f
            else par_single_spr_round a b c d e f
    ELSE
        single_spr_round a b c d e f
    END


let spr_join pb tabu search breakage =
    match single_spr_round pb `Right `Left tabu search breakage with
    | Tree.Skip | Tree.Continue -> 
        single_spr_round pb `Left `Right tabu search breakage
    | x -> x


let tbr_join pb tabu search breakage =
    let reroot_on_edge tabu to_reroot edge breakage =
        let ptree, inc =
            Tree_Ops.reroot_fn (tabu#get_node_manager) true edge breakage.ptree
        in
        let Tree.Edge (a, b) = Tree.normalize_edge edge ptree.tree in
        let create_clade_info clade_info =
            let handle = handle_of a ptree in
            match clade_info.topology_delta with
            | `Edge (w, x, y, z) ->
                    { clade_info with 
                        clade_node = get_component_root_median handle ptree;
                        topology_delta = `Edge (w, a, b, Some handle);
                    }
            | `Single _ -> assert false
        in
        let breakage =
            let left, right = breakage.tree_delta in
            match to_reroot with
            | `Left -> 
                    let clade_info = create_clade_info breakage.left in
                    { breakage with left = clade_info; 
                        tree_delta = (clade_info.topology_delta, right) }
            | `Right -> 
                    let clade_info = create_clade_info breakage.right in
                    { breakage with right = clade_info; 
                        tree_delta = (left, clade_info.topology_delta) }
        in
        apply_incremental { breakage with ptree = ptree; incremental = inc }
    in
    let breakage = apply_incremental breakage in
    let rec do_search search_breakage =
        match single_spr_round pb `Left `Right tabu#clone search search_breakage with
        | Tree.Break as x -> x
        | Tree.Skip | Tree.Continue ->
                let to_reroot = `Right in
                match breakage.tree_delta with
                | (`Single _), _ | _, (`Single _) -> Tree.Continue
                | (`Edge _), (`Edge _) ->
                        match tabu#reroot_edge to_reroot with
                        | None -> 
                                Tree.Continue
                        | Some ((Tree.Edge (a, b)) as edge) ->
                                if debug then
                                    Printf.printf "Rerooting in %d %d\n%!" a b;
                                let search_breakage = 
                                    reroot_on_edge tabu to_reroot edge breakage 
                                in
                                tabu#update_reroot search_breakage;
                                do_search search_breakage
    in
    do_search breakage


let breakage_to_pb x = `Pair x.tree_delta


let do_search neighborhood (tree: ('a,'b) p_tree) 
                           (tabu: ('a,'b) tabu_mgr)
                           (search : ('a,'b) search_mgr) : unit =
    let rec do_search () =
        match tabu#break_edge with
        | None -> Tree.Break
        | Some (Tree.Edge ((a, b) as x)) -> 
            let breakage = Tree_Ops.break_fn (tabu#get_node_manager) x tree in
            let breakage = apply_incremental breakage in
            let new_tabu = tabu#clone in
            new_tabu#update_break breakage;
            (* We use pb to avoid evaluating again the initial tree *)
            let pb = breakage_to_pb breakage in
            match neighborhood pb new_tabu search breakage with
            | Tree.Break as x -> x
            | Tree.Skip | Tree.Continue -> do_search ()
    in
    match do_search () with
    | Tree.Break | Tree.Skip | Tree.Continue -> ()


let tbr_step a b c = 
    do_search tbr_join a b c;
    c


let spr_step a b c = 
    do_search spr_join a b c;
    c


let search (passit:bool) (searcher, name) (search : ('a,'b) search_mgr) : ('a, 'b) search_mgr =
    if debug_search_fn then Printf.printf "ptree.search,%!";
    let status = Status.create name None ("Searching") in
    try
        while search#any_trees do
            let (ptree, cost, tabu) = search#next_tree in
            if debug_search_fn then Printf.printf "ptree.search next_tree with cost = %f\n%!" cost;
            Status.full_report ~msg:(string_of_float cost) ~adv:(int_of_float cost) status;
            searcher ptree tabu#clone search;
        done;
        Status.finished status;
        search
    with
    | Methods.TimedOut when not passit -> 
            Status.finished status;
            search


(** This function will not find the local optimum, it will return as soon as a
    better tree is found. *)
let search_local_next_best (searcher, name) (search : (Tree_Ops.a, Tree_Ops.b) search_mgr)
        : (Tree_Ops.a, Tree_Ops.b) search_mgr =
    let status = Status.create ("Single " ^ name) None ("Searching") in
    let ptree, cost, tabu = search#next_tree in
    try
        searcher ptree tabu#clone search;
        Status.finished status;
        search
    with Methods.TimedOut -> search

let spr_simple x = search x (do_search spr_join, "SPR")

let tbr_simple x = search x (do_search tbr_join, "TBR")

let spr_single = search_local_next_best (do_search spr_join, "SPR")

let tbr_single = search_local_next_best (do_search tbr_join, "TBR")

let tbr_join a b c = tbr_join (breakage_to_pb c) a b c

let spr_join a b c = spr_join (breakage_to_pb c) a b c


let alternate spr tbr search =
    let find_best_cost lst =
        List.fold_left
            (fun best (_, cost, _) -> if best < cost then best else cost)
            max_float lst
    in
    let status = Status.create "Alternate" None ("") in
    let () = Status.full_report ~msg:("Beginning search") status in
    let rec try_spr prev_best search = match search#any_trees with
      | false -> search
      | true ->
          Status.full_report ~msg:("SPR search") status;
          let search, timedout =
              try spr search, false
              with Methods.TimedOut -> search, true
          in
          if timedout then search
          else
              (* SPR is done---run TBR steps on the results *)
              let () = Status.full_report ~msg:"Performing TBR swapping" status in
              let results = search#results in
              let best_cost = find_best_cost results in
              let search = search#clone in
              let () =
                  search#init
                    (List.map (fun (tree, cost, tabu) -> tree, cost, NoCost, tabu)
                              results)
              in
              let search, timedout =
                  try tbr search, false with
                  | Methods.TimedOut -> search, true
              in
              if timedout then
                search
              else
                let new_cost = find_best_cost search#results in
                if (new_cost < best_cost && new_cost < prev_best) || search#should_repeat then
                    let search = search#clone in
                    let () =
                        search#init
                            (List.map (fun (tree, cost, tabu) -> tree, cost, NoCost, tabu)
                                      results)
                    in
                    try_spr new_cost search
                else
                    search
    in
    let search = try_spr max_float search in
    Status.finished status;
    search


let repeat_until_no_more tabu_creator neighborhood queue =
    Status.user_message Status.Information "Starting on tree";
    let rec go queue =
        let queue = neighborhood queue in
        if queue#should_repeat then 
            let results = queue#results in
            let queue = queue#clone in
            let _ =
                queue#init
                (List.map (fun (tree, cost, tbu) -> tree, cost,
                NoCost, tabu_creator tree)
                results);
            in
            go queue
        else queue
    in
    let res = go queue in
    res

    (** @return the number of trees considered during the search. *)
    let get_trees_considered () = !trees_considered

    (** @return Sets the number of trees considered to zero. *)
    let reset_trees_considered () = trees_considered := 0


(** {2 Tree Fusing} *)
type ('a, 'b) fuse_locations =
        (('a, 'b) p_tree * Tree.u_tree * Tree.edge) list Sexpr.t


let fuse_all_locations ?min ?max trees =
    let min = match min with
        | Some x when x < 3 -> Some 3
        | None -> Some 3 
        | x -> x
    in
    let filter = match min, max with
        | None, None         -> (fun _ -> true)
        | Some min, None     -> (fun (_, s) -> s >= min)
        | None, Some max     -> (fun (_, s) -> s <= max)
        | Some min, Some max -> (fun x -> Tree.fuse_cladesize ~min ~max x)
    in
    let trees = List.map (fun ((t,_) as x) -> (x,t.tree)) trees in
    let res = Tree.fuse_all_locations ~filter trees in
(*    Printf.printf "Found Fusing Locations (%d):\n%!" (Sexpr.length res);*)
(*    Sexpr.leaf_iter*)
(*        (fun x ->*)
(*            List.iter*)
(*                (fun (_,t,(Tree.Edge (a,b))) ->*)
(*                    Printf.printf "\t%d--%d\n%!" a b)*)
(*                x)*)
(*        res;*)
    res


let fuse source_arg target_arg =
    let adjust_mgr = 
(*        let _,_,_,adj1 = source_arg and _,_,_,adj2 = target_arg in*)
(*        Some  (new nodes_manager adj1 adj2)*)
        None
    in
    (* reroot if necessary *)
    let maybe_reroot ((tree, utree, (Tree.Edge(efrom, eto) as edge)) as arg) =
        if is_edge edge tree then arg
        else
            let tree, updt = Tree_Ops.reroot_fn adjust_mgr false edge tree in
            let tree = Tree_Ops.incremental_uppass tree updt in
            tree, tree.tree, edge
    in
    let source, source_u, sedge = maybe_reroot source_arg in
    let target, target_u, tedge = maybe_reroot target_arg in
    assert (is_edge sedge source);
    assert (is_edge tedge target);
    let u_tree =
        Tree.fuse ~source:(source_u, sedge) ~target:(target_u, tedge) 
    in
    let res = { target with tree = u_tree } in
    diagnosis res


let destroy_component handle tree =
    let cleanup_node v tree =
        if All_sets.IntegerMap.mem v tree.tree.Tree.u_topo then
            (* This is a leaf so we have to leave the data in and make sure that
            * we add it as a root of the tree *)
            let data = get_node_data v tree in
            let root = 
                { root_median = (Some ((`Single v), data));
                component_cost = 0.;
                adjusted_component_cost = 0.; }
            in
            { tree with component_root = All_sets.IntegerMap.add v root
            tree.component_root }
        else remove_node_data v tree
    in
    let my_remove_edge_data edge ptree =
        let edge2 = 
            let Tree.Edge (a, b) = edge in 
            Tree.Edge (b, a) 
        in
        let new_edge_data =
            ptree.edge_data 
            --> Tree.EdgeMap.remove edge 
            --> Tree.EdgeMap.remove edge2
        in
        { ptree with edge_data = new_edge_data }
    in
    let edges = Tree.get_pre_order_edges handle tree.tree in
    let tree = { tree with tree = Tree.destroy_component handle tree.tree } in
    List.fold_left (fun acc ((Tree.Edge (a, b)) as e) ->
        acc -->  cleanup_node a --> cleanup_node b -->
            my_remove_edge_data e) 
        tree edges


let copy_component handle source target =
    let target = 
        let tree =
            target.tree --> Tree.copy_component handle source.tree
        in
        { target with tree = tree }
    in
    let edges = Tree.get_pre_order_edges handle source.tree in
    let target = 
        List.fold_left (fun acc ((Tree.Edge (a, b)) as e) ->
            let e = Tree.normalize_edge e source.tree in
            acc
            --> (fun acc ->
                try 
                    let data = get_edge_data e source in
                    add_edge_data e data acc
                with
                | Not_found -> acc)
            --> add_node_data a (get_node_data a source)
            --> add_node_data b (get_node_data b source)
            --> remove_root_of_component a 
            --> remove_root_of_component b) target edges
    in
    let root = get_component_root handle source in
    { target with component_root = All_sets.IntegerMap.add handle root
    target.component_root }


let fuse source target terminals =
    let adj_1,adj_2 = 
        let ((_,adj1),_,_) = source and ((_,adj2),_,_) = target in
        adj1, adj2
    in
    let debug = false in
    let maybe_reroot (((tree, adj), utree, (Tree.Edge(efrom, eto) as edge))) =
        let tree, updt = Tree_Ops.reroot_fn (Some adj) false edge tree in
        let tree = Tree_Ops.incremental_uppass tree updt in
        tree, tree.tree, edge 
    in
    let count = 1000000 in
    let (stree, sutree, sedge) = maybe_reroot source
    and (ttree, tutree, tedge) = maybe_reroot target in
    let original = stree in
    let shash, scode, stree = edge_recode stree sedge count
    and thash, tcode, ttree = edge_recode ttree tedge count in
    let fix_edge tbl (Tree.Edge (a, b)) = 
        try Tree.Edge (Hashtbl.find tbl a, Hashtbl.find tbl b) with
        | Not_found as err ->
                Printf.printf "The codes are %d and %d\n%!" a b;
                raise err
    in
    let terminals = terminals + 1 in
    let shash1, scode, stree = 
        edge_recode stree (fix_edge shash sedge) terminals
    and thash1, tcode, ttree = 
        edge_recode ttree (fix_edge thash tedge) terminals 
    in
    assert (scode = tcode);
    let (sa, sb) as sedge =
        let (Tree.Edge (sa, sb)) = sedge in
        Hashtbl.find shash1 (Hashtbl.find shash sa), 
        Hashtbl.find shash1 (Hashtbl.find shash sb)
    and (ta, tb) as tedge = 
        let (Tree.Edge (ta, tb)) = tedge in
        Hashtbl.find thash1 (Hashtbl.find thash ta),
        Hashtbl.find thash1 (Hashtbl.find thash tb) 
    in
    assert (ta = sa);
    assert (tb = sb);
    if debug then prerr_endline "About to break";
    let stree, (sld, srd), sinc = 
        let breakage = Tree_Ops.break_fn (Some adj_1) sedge stree in
        breakage.ptree, breakage.tree_delta, breakage.incremental
    and ttree, (tld, trd), tinc = 
        let breakage = Tree_Ops.break_fn (Some adj_2) tedge ttree in
        breakage.ptree, breakage.tree_delta, breakage.incremental
    in
    let stree = Tree_Ops.incremental_uppass stree sinc
    and ttree = Tree_Ops.incremental_uppass ttree tinc in
    if debug then prerr_endline "Finished uppass";
    let tree, jxn =
        match trd, srd with
        | (`Edge (_, la, lb, _)), (`Edge (_, ra, rb, _)) ->
                let ttree =
                    ttree --> destroy_component (handle_of lb ttree) 
                          --> copy_component (handle_of rb stree) stree
                in
                ttree, (Tree.Edge_Jxn (ra, rb))
        | (`Single (x, _)), _
        | _, (`Single (x, _)) -> original, (Tree.Single_Jxn x)
    in
    let jxn2 = match tld with
        | `Edge (_, la, lb, _) -> (Tree.Edge_Jxn (la, lb))
        | `Single (x, _) -> Tree.Single_Jxn x
    in
    let adj_3 = adj_1#fuse adj_2 in
    let tree, _ = Tree_Ops.join_fn (Some adj_3) [] jxn jxn2 tree in
    let tree = Tree_Ops.uppass tree in
    tree,adj_3


(** [fuse_generations trees max_trees tree_weight tree_keep iterations process]
    runs a genetic algorithm-style search using tree fusing.  The function takes a
    list of trees to start with, the max number of trees and a method for keeping
    trees, a method for weighting trees, a number of iterations to perform, and a
    function to process new trees *)
let fuse_generations trees terminals max_trees tree_weight tree_keep
                        iterations process (cmin, cmax) =
    let () = 
        if 2 > List.length trees then 
            failwith "Tree fusing: must have at least two trees";
    in
    let status = Status.create "Tree Fusing" (Some iterations) "" in
    let () = Status.full_report status in
    (* remove lowest cost trees from list so length equals max_trees *)
    let limit_num trees =
        let len = List.length trees in
        let trees = List.sort (fun (a,_) (b,_) -> 
            compare (get_cost `Adjusted b) (get_cost `Adjusted a))  trees 
        in
        let trees = ref trees in
        for i = (len - max_trees) downto 1 do
            trees := match !trees with | h :: t -> t | [] -> []
        done; 
        !trees 
    in
    let keeper new_trees source target trees' = match tree_keep with
        | `Best ->
            let old_trees = source :: target :: trees' in
            limit_num (List.rev_append new_trees old_trees)
        | `Better ->
            let target_cost = get_cost `Adjusted (fst target) in
            let new_trees =
                List.filter (fun (t,_) -> target_cost >= get_cost `Adjusted t) new_trees
            in
            begin match new_trees with
                | [] -> source :: target :: trees'
                | new_trees ->
                    let old_trees =
                        if (List.length new_trees + List.length trees' + 1) >= max_trees then 
                            source :: trees'
                        else
                            source :: target :: trees'
                    in
                    limit_num (List.rev_append new_trees old_trees)
            end
    in
    let rec choose_remove ?(i=1) f weights items = match weights with
        | w :: ws ->
            if w >= f then
                List.hd items, i, ws, List.tl items
            else 
                let c, i, ws, is = 
                    let tl = List.tl items in
                    choose_remove ~i:(succ i) (f -. w) ws tl
                in
                c, i, w :: ws, (List.hd items) :: is
        | [] -> failwith "choose_remove" 
    in
    let choose_remove f weights items =
        assert (List.length weights = List.length items);
        assert (f <= List.fold_left ( +. ) 0. weights);
        try choose_remove f weights items
        with Failure "choose_remove" ->
            let msg =
                Printf.sprintf
                    "Warning: choose_remove: total weight %f; f = %f; len = %d"
                    (List.fold_left ( +. ) 0. weights) f (List.length weights)
            in
            odebug msg;
            List.hd items, 1, List.tl weights, List.tl items
    in
    let module FPSet = Set.Make (Tree.Fingerprint) in
    let rec gen fp trees iter =
        if iter > iterations then trees
        else begin
            let trees = limit_num trees in
            Status.full_report ~adv:iter status;
            let weights = List.map (fun (t,_) -> tree_weight t) trees in
            let wsum = List.fold_left (+.) 0. weights in
            let source, snum, weights, trees' =
                choose_remove (Random.float wsum) weights trees in
            let wsum = List.fold_left (+.) 0. weights in
            let target, tnum, weights, trees' =
                choose_remove (Random.float wsum) weights trees' in
            let msg =
                Printf.sprintf "tree #%d [%f] -> tree #%d [%f]"
                               snum (get_cost `Adjusted (fst source))
                               tnum (get_cost `Adjusted (fst target))
            in
            let locations = fuse_all_locations ~min:cmin ~max:cmax [source; target] in
            (* let location = Sexpr.choose_random locations in *)
            let process_location location = match location with
                | [t1; t2] ->
                    let t1, t2 = match t1 with
                        | ((tree,_), _, _) when tree == (fst source) -> t1, t2
                        | ((tree,_), _, _) when tree == (fst target) -> t1, t2
                        | _ -> assert false in
                    let new_tree,a3 = fuse t1 t2 terminals in
                    Status.full_report 
                        ~msg:(msg ^ ": tree with cost " ^ string_of_float (get_cost `Adjusted new_tree))
                        status;
                    (new_tree,a3)
                | _ -> assert false
            in
            let new_tree, _ =
                Sexpr.fold_left
                    (fun ((res,cost) as acc) x ->
                        let new_tree = process_location x in
                        let new_cost = get_cost `Adjusted (fst new_tree) in
                        if new_cost <  cost then Some new_tree, new_cost
                        else acc)
                    (None, get_cost `Adjusted (fst target))
                    locations
            in
            let fp, trees = match new_tree with
                | None -> fp, trees
                | Some (new_tree,adj) ->
                    let nfp = Tree.Fingerprint.fingerprint new_tree.tree in
                    if FPSet.mem nfp fp then
                        fp, keeper [(new_tree,adj)] source target trees'
                    else
                        let new_trees =
                            List.map (fun t -> t,adj#clone) (process new_tree) in
                        let fp =
                            List.fold_left
                                (fun acc (x,_) ->
                                    FPSet.add (Tree.Fingerprint.fingerprint x.tree) acc)
                                fp
                                new_trees
                        in
                        fp, keeper new_trees source target trees'
            in
            gen fp trees (succ iter)
        end
    in
    let remove_managers xs = List.map (fun (x,_) -> x) xs in
    let res = 
        let fp = 
            List.fold_left 
                (fun acc (x,_) -> FPSet.add (Tree.Fingerprint.fingerprint x.tree) acc)
                FPSet.empty trees
        in
        gen fp trees 1
    in
    Status.finished status;
    remove_managers (limit_num res)

(** [convert_to tree d]
    @param tree the Tree.Parse.t that is being used to build trees.
    @param d Data.d the data associated with the parser tree.
    @return p_tree that corresponds to the Tree.Parse.t *)
let convert_to tree (data, nd_data_lst) = 
    (* convert the Tree.Parse.t to Tree.u_tree *)
    let ut = Tree.Parse.convert_to tree (fun taxon -> Data.taxon_code taxon data) in
    let pt = { (empty data) with tree = ut } in
    (* function to add leaf-node data to the ptree. *)
    let data_adder ptree nd = add_node_data (Node.taxon_code nd) nd ptree in
    List.fold_left data_adder pt nd_data_lst


let build_trees = build_trees

(** [build_tree tree]
    @param tree the ptree being converted into a Tree.Parse.t
    @return the tree with the smallest handle_id in ptree *)
let build_tree tree strgen name_subtree name_tree collapse branches characters root =
    let map = 
        build_trees tree strgen name_subtree name_tree collapse branches characters root
    in
    List.hd map

let basic_build_trees tree strgen collapse branches chars root =
    let trees = 
        build_trees tree strgen (fun _ _ _ _ -> None) (fun _ _ -> "")
                    collapse branches chars root
    in
    List.map (snd) trees


let basic_build_tree tree strgen collapse branches chars root =
    let trees =
        basic_build_trees tree strgen collapse branches chars root
    in
    List.hd trees


let get_collapse_function t = match t with
    | None    -> (fun _ _ _ -> false)
    | Some st ->
        (fun tree code chld ->
            let rec sum_branch acc = function
                | [] -> acc
                | (_,Some x)::tl -> sum_branch (acc+.x) tl
                | (_,None  )::tl -> sum_branch  acc     tl
            in
            let a = get_node_data code tree in
            let b = get_node_data chld tree in
            let r =
                let adjusted      = false (* edge-distance always uses unadjusted *)
                and inc_parsimony = (true,t) in
                Node.get_times_between ~adjusted ~inc_parsimony a (Some b)
            in
            0.0 = sum_branch 0.0 r)

let default_collapse_function =
    get_collapse_function (Some `Single)

let extract_names ptree code = 
    let data = get_node_data code ptree in
    try Data.code_taxon (Node.taxon_code data) ptree.data
    with _ -> ""

let extract_codes pd ptree code = string_of_int code

let build_tree_with_codes tree pd =
    basic_build_tree tree.tree (extract_codes pd tree)
                (default_collapse_function tree) None None (fun _ -> "")

let rec fold_2 f acc a b = match a, b with
    | (ha :: ta), (hb :: tb) -> fold_2 f (f acc ha hb) ta tb
    | [], [] -> acc
    | _, _ -> false

let rec compare_trees a b =
    let rec compare acc a b = 
        acc &&
        (match a, b with
        | Tree.Parse.Leafp x, Tree.Parse.Leafp y ->  x = y
        | Tree.Parse.Nodep (ca, _), Tree.Parse.Nodep (cb, _) ->
                fold_2 compare true ca cb
        | _, _ -> false)
    in
    compare true (Tree.Parse.strip_tree a) (Tree.Parse.strip_tree b)
 
let get_unique_fn get_tree get_cost datas =
  let build_tree_with_codes tree =
    basic_build_tree tree (string_of_int) (fun _ _ -> false) None None (fun _ -> "")
  in
  match datas with
    | tree :: _ ->
        let a, _ = Tree.choose_leaf (get_tree tree) in
        let datas =
            List.sort
                (fun x y -> Pervasives.compare (get_cost x) (get_cost y))
                datas
        in
        let datas =
            List.rev_map
                (fun x -> x, Tree.cannonize_on_leaf a (get_tree x))
                datas
        in
        let datas =
            List.rev_map
                (fun (x, y) -> x,Tree.Parse.cannonic_order (build_tree_with_codes y))
                datas
        in
        let rec remove_duplicated acc = function
            | (x, y) :: t ->
                let are_different (_, z) = not (compare_trees y z) in
                remove_duplicated (x :: acc) (List.filter are_different t)
            | [] -> acc
        in
        remove_duplicated [] datas
    | x -> x


let get_unique = get_unique_fn (fun x -> x.tree) (fun x -> get_cost `Adjusted x)


(** [build_tree_with_names tree pd]
    @return What does this function do? *)
let build_tree_with_names collapse tree =
    let collapse_f = get_collapse_function collapse tree in
    basic_build_tree tree.tree (extract_names tree) collapse_f None None (fun _ -> "")


let build_forest_with_names collapse tree =
    let collapse_f = get_collapse_function collapse tree in
    basic_build_trees tree.tree (extract_names tree) collapse_f None None (fun _ -> "")


let build_tree_with_names_n_costs collapse tree cost = 
    let collapse_f = get_collapse_function collapse tree in
    let extract_names code =
        let data = get_node_data code tree in
        match get_node code tree with
        | Tree.Interior (_, par, _, _) ->
            string_of_float (Node.total_cost (Some par) data)
        | _ ->
            try Data.code_taxon (Node.taxon_code data) tree.data
            with _ -> ""
    and root_name tree = function
        | None   -> cost
        | Some c -> 
            (Some (Array.to_list c))
                --> Tree_Ops.total_cost tree `Adjusted
                --> string_of_float
    in
    basic_build_tree tree.tree extract_names collapse_f None None (root_name tree)


let build_forest collapse tree cost =
    let collapse_f = get_collapse_function collapse tree in
    let extract_names code =
        let data = get_node_data code tree in
        match get_node code tree with
        | Tree.Interior (_, par, _, _) -> ""
        | _ -> try Data.code_taxon (Node.taxon_code data) tree.data
               with _ -> ""
    and root_name tree = function
        | None   -> cost
        | Some c -> 
            (Some (Array.to_list c))
                --> Tree_Ops.total_cost tree `Adjusted
                --> string_of_float
    in
    basic_build_trees tree.tree extract_names collapse_f None None (root_name tree)


let rec build_forest_as_tree collapse tree cost =
    match build_forest collapse tree cost with
    | [tree] -> tree
    | []     -> failwith "no trees?"
    | trees  ->
        let trees = List.map Tree.Parse.remove_annotations trees in
        begin match List.hd trees with
        | Tree.Parse.Annotated (t,str) -> assert false
        | Tree.Parse.Flat t ->
            let chillens = List.map 
                (fun x -> match x with
                    | Tree.Parse.Flat x -> x
                    | _ -> failwith "consistency")
                trees
            in
            Tree.Parse.Flat (Tree.Parse.Nodep (chillens, "forest"))
        | Tree.Parse.Characters t ->
            let chillens = List.map 
                (fun x -> match x with
                    | Tree.Parse.Characters x -> x
                    | _ -> failwith "consistency")
                trees
            in
            Tree.Parse.Characters (Tree.Parse.Nodep (chillens, ("forest",None)))
        | Tree.Parse.Branches t ->
            let chillens = List.map 
                (fun x -> match x with
                    | Tree.Parse.Branches x -> x
                    | _ -> failwith "consistency")
                trees
            in
            Tree.Parse.Branches (Tree.Parse.Nodep (chillens, ("forest",None)))
    end


let build_forest_with_names_n_costs collapse tree cost branches chars = 
    let collapse_f = get_collapse_function collapse tree in
    let extract_names code =
        let data = get_node_data code tree in
        match get_node code tree with
        | Tree.Interior (_, par, _, _) ->
               string_of_float (Node.total_cost (Some par) data)
        | _ -> try Data.code_taxon (Node.taxon_code data) tree.data
               with _ -> ""
    and root_name tree = function
        | None   -> cost
        | Some c ->
            (Some (Array.to_list c))
                --> Tree_Ops.total_cost tree `Adjusted
                --> string_of_float
    in
    let branches = 
        if fst branches
            then Some (Tree_Ops.branch_table (snd branches) tree)
            else None
    in
    basic_build_trees tree.tree extract_names collapse_f branches chars (root_name tree)


let build_forest_with_names_n_costs_n_branches collapse tree cost gen_label gen_tree branches chars =
    let collapse_f = get_collapse_function collapse tree in
    let extract_names code =
        let data = get_node_data code tree in
        match get_node code tree with
        | Tree.Interior (_, par, _, _) ->
               string_of_float (Node.total_cost (Some par) data)
        | _ -> try Data.code_taxon (Node.taxon_code data) tree.data
               with _ -> ""
    and root_name tree = function
        | None   -> cost
        | Some c -> 
            (Some (Array.to_list c))
                --> Tree_Ops.total_cost tree `Adjusted
                --> string_of_float
    in
    let branches = 
        if fst branches
            then Some (Tree_Ops.branch_table (snd branches) tree)
            else None
    in
    build_trees tree.tree extract_names gen_label gen_tree
                collapse_f branches chars (root_name tree)


(** [disp_trees tree]
    @param str the title of the image.
    @param tree the ptree being displayed. 
    @return the tree is drawn either in graphical format or ascii format. *)
let disp_trees str tree strgen root =
    let root_name tree = function
        | None   -> root
        | Some c ->
            (Some (Array.to_list c))
                --> Tree_Ops.total_cost tree `Adjusted
                --> string_of_float
    in
    let trees =
        ref (basic_build_trees tree.tree (strgen tree) 
                (default_collapse_function tree) None None (root_name tree))
    in
    let ntrees = List.length !trees in
    let get_tree () = List.hd !trees in
    for i = 1 to ntrees do
        print_endline (str ^ ": " ^ string_of_int i ^ "/" ^ string_of_int ntrees);
        AsciiTree.draw false stdout (get_tree ());
        trees := List.tl !trees
    done


(** [to_xml tree data f]
@param tree the ptree which is being converted into a Tree.Parse.t
@return the ptree in the form of a Tree.Parse.t *)
let to_xml ch tree =
    let rec rec_down node prev_node =
        match node with
        | Tree.Leaf (self, parent) -> 
                output_string ch "<otu>\n";
                flush ch;
                let data = get_node_data self tree in
                Node.to_xml tree.data ch data;
                output_string ch "</otu>\n";
                flush ch;
        | Tree.Interior (our_id, _, _, _) ->
                let data = get_node_data our_id tree in
                let (ch1, ch2) = 
                    assert (prev_node <> Tree.get_id node);
                    Tree.other_two_nbrs prev_node node in
                output_string ch "<htu>\n";
                flush ch;
                Node.to_xml tree.data ch data;
                flush ch;
                rec_down (get_node ch1 tree) our_id;
                rec_down (get_node ch2 tree) our_id;
                output_string ch "</htu>\n";
                flush ch;
        | Tree.Single _ -> failwith "Unexpected single"
    in
    let print_item handle =
        output_string ch "<tree>\n";
        begin match get_node handle tree with
        | Tree.Leaf (self, parent) ->
                rec_down (get_node parent tree) handle
        | Tree.Interior (self, par, ch1, ch2) ->
                (* rec_down (get_node par tree) self; *)
                rec_down (get_node ch1 tree) self;
                rec_down (get_node ch2 tree) self;
                Node.to_xml tree.data ch (get_node_data self tree);
        | Tree.Single self -> ()
        end;
        output_string ch "</tree>\n"
    in
    All_sets.Integers.iter print_item (get_handles tree)

  end



module Fingerprint = struct
    type t = Tree.Fingerprint.t
    let fingerprint {tree=t} = Tree.Fingerprint.fingerprint t
    let compare = Tree.Fingerprint.compare
end

let get_leaves ?(init=[]) root t =
    match get_node root t with
    | Tree.Single _ -> (get_node_data root t) :: init
    | _ ->
        pre_order_node_visit
            (fun parent node_id acc ->
                try match get_node node_id t with
                    | Tree.Leaf _ -> (Tree.Continue, (get_node_data node_id t) :: acc)
                     | _ -> (Tree.Continue, acc)
                with | Not_found as err -> 
                    Status.user_message Status.Information 
                        ("Failed with code " ^ string_of_int node_id);
                    raise err)
            root t init

let get_all_leaves t =
    All_sets.Integers.fold
        (fun h init -> get_leaves ~init h t)
        t.tree.Tree.handles
        []

let select_default adjusted cost = match adjusted with
    | Some v -> v
    | None -> cost

let assign_root_to_connected_component handle item cost adjusted ptree =
    let adjusted = select_default adjusted cost in
    let root =
        { root_median = item;
          component_cost = cost;
          adjusted_component_cost = adjusted 
        }
    in
    let new_component =
        All_sets.IntegerMap.add handle root ptree.component_root 
    in
    { ptree with component_root = new_component; }

let get_handle_cost adjusted ptree handle_id =
    let res = All_sets.IntegerMap.find handle_id ptree.component_root in
    match adjusted with
    | `Unadjusted -> res.component_cost
    | `Adjusted -> res.adjusted_component_cost

let get_all_leaves_ids t =
    let get_leaves_ids ?(init=[]) root t =
        pre_order_node_visit
            (fun parent node_id acc -> match get_node node_id t with
                 | Tree.Single _ | Tree.Leaf _ -> (Tree.Continue, node_id :: acc)
                 | _ -> (Tree.Continue, acc))
            root t init
    in
    All_sets.Integers.fold
        (fun h init -> get_leaves_ids ~init h t)
        t.tree.Tree.handles
        []

(** [break_median ptree id] creates two trees from one by removing one of the
    edges incident to [id].  ([id] must be an internal node.)  If the neighbors
    of [id] are a, b, and c, it does this by comparing the medians (a, b), (b,
    c), and (a, c); it keeps the shortest edge. *)
let break_median_edge medianfn id ptree =
    match get_node id ptree with
    | Tree.Interior (self, a, b, c) ->
          let da, db, dc =
              get_parent_or_root_data self ptree,
              get_node_data b ptree,
              get_node_data c ptree in
          (* calculate the medians *)
            let self = Some self in
          let mab = medianfn self self da db in
          let mac = medianfn self self da dc in
          let mbc = medianfn self self db dc in
          (* break the longest edge *)
          if mab <= mac && mab <= mbc
          then Tree.Edge (id, c)
          else if mac <= mab && mac <= mbc
          then Tree.Edge (id, b)
          else if mbc <= mab && mbc <= mac
          then Tree.Edge (id, a)
          else failwith "break_median_edge"
    | _ -> failwith "break_median_edge1"

(** [jxn_of_handle ptree handle] returns the junction corresponding to a
    handle's position in the tree (forest) *)
let jxn_of_handle ptree handle =
    Tree.test_tree ptree.tree;
    match get_node handle ptree with
    | Tree.Single n -> Tree.Single_Jxn n
    | Tree.Interior (id, par, _, _)
    | Tree.Leaf (id, par) ->
          if ndebug_jxn_of_handle
          then (odebug ("jxn of handle with id " ^ string_of_int id
                        ^ " and parent " ^ string_of_int par);
                ignore(get_node par ptree);
                odebug "Parent node exists");
          Tree.Edge_Jxn (id, par)

let add_or_not addme set counters = 
    if (not addme) && Tree.CladeFPMap.mem set counters then
        let res = Tree.CladeFPMap.find set counters in
        set, Tree.CladeFPMap.add set (res + 1) counters
    else if not addme then
        set, Tree.CladeFPMap.add set 1 counters
    else set, counters

(* A function that takes a map of counts of sets of terminals, and a tree, and
* adds the sets defined by tree to the counters *)
let add_tree_to_counters is_collapsable counters (tree : Tree.u_tree) = 
    let rec add_all_clades node prev counters =
        let addme = is_collapsable prev node in
        let add_singleton () =
            let single = All_sets.Integers.singleton node in
            add_or_not false single counters
        in
        match Tree.get_node node tree with
        | Tree.Leaf _ 
        | Tree.Single _ -> add_singleton ()
        | Tree.Interior (_, a, b, c) ->
            let a, b = 
                if a = prev then b, c
                else if b = prev then a, c
                else if c = prev then a, b
                else failwith "Tree.consensus"
            in
            let sidea, counters = add_all_clades a node counters in
            let sideb, counters = add_all_clades b node counters in
            let mine = All_sets.Integers.union sidea sideb in
            add_or_not addme mine counters
    in
    let add_handle tree handle counters = 
        match Tree.get_node handle tree with
        | Tree.Leaf (a, b) 
        | Tree.Interior (a, b, _, _) ->
            let sidea, counters = add_all_clades a b counters in
            let sideb, counters = add_all_clades b a counters in
            let mine = All_sets.Integers.union sidea sideb in
            let _, res = add_or_not false mine counters in
            res
        | Tree.Single _ -> 
            let _, res = add_all_clades handle handle counters in
            res
    in
    All_sets.Integers.fold (add_handle tree) (Tree.get_handles tree) counters


let make_tree_counters code_generator counters gen_tree = 
    let add_singleton node =
        let single = All_sets.Integers.singleton node in
        add_or_not false single counters
    in
    let rec make_tree_counters counters tree = match tree with
        | Tree.Parse.Leafp d -> add_singleton (code_generator d)
        | Tree.Parse.Nodep (lst, _) ->
            let all_sets, counters =
                List.fold_left
                    (fun (all_sets, counters) child ->
                        let its_sets, counters = make_tree_counters counters child in
                        (its_sets :: all_sets, counters))
                    ([], counters)
                    lst
            in
            let all_sets =
                List.fold_left
                    All_sets.Integers.union
                    All_sets.Integers.empty
                    all_sets
            in
            add_or_not false all_sets counters
    in
    make_tree_counters counters (Tree.Parse.strip_tree gen_tree)


let add_consensus_to_counters counters trees = 
    let new_counter = 
        List.fold_left
            (fun acc (is_collapsable, b) ->
                add_tree_to_counters is_collapsable acc b)
            Tree.CladeFPMap.empty trees
    in
    let len = List.length trees in
    (* We proceed to add those clades that appear in all of the trees *)
    Tree.CladeFPMap.fold
        (fun set count acc ->
            if count = len
                then snd (add_or_not false set acc)
                else acc)
        new_counter counters


let build_a_tree to_string denominator print_frequency coder trees ((set,cnt) : Tree.CladeFPMap.key * float) =
    let module CladeFPSet = Set.Make (Tree.CladeFP.Ordered) in
    let all_trees, _, trees = 
        All_sets.Integers.fold 
            (fun x (my_trees, sets, builttrees) ->
                try
                    let trees, clades = All_sets.IntegerMap.find x builttrees in
                    if CladeFPSet.mem clades sets then
                        my_trees, sets, builttrees
                    else
                        let sets = CladeFPSet.add clades sets in
                        trees :: my_trees, sets, builttrees
                with | Not_found ->
                    assert (1 = All_sets.Integers.cardinal set);
                    let code = All_sets.Integers.choose set in
                    coder := code;
                    let name = to_string code in
                    let newtree = Tree.Parse.Flat (Tree.Parse.Leafp name) in
                    let trees = 
                        All_sets.IntegerMap.add code (newtree, set) builttrees 
                    in
                    newtree :: my_trees, sets, trees)
            set 
            ([], CladeFPSet.empty, trees)
    in
    let tree = match all_trees with
        | [] -> failwith "Tree.consensus2"
        | [all_trees] -> all_trees
        |  all_trees  ->
            let x = cnt /. denominator in
            let prec = Str.string_match (Str.regexp ".*\\.[0-9]+")
                                        (Printf.sprintf "%F" x) 0 in
            let msg =
                if print_frequency && prec
                    then Printf.sprintf "%0.4f" x
                else if print_frequency
                    then Printf.sprintf "%0.F" x
                    else ""
            in
            let all_trees = List.map (Tree.Parse.strip_tree) all_trees in
            Tree.Parse.Flat (Tree.Parse.Nodep (all_trees, msg))
    in
    All_sets.Integers.fold
        (fun x trees ->
            All_sets.IntegerMap.add x (tree, set) trees)
        set
        trees

let make_tree (majority_cutoff : 'a) (coder : All_sets.IntegerMap.key ref)
              (builder : ('b * 'c) All_sets.IntegerMap.t -> Tree.CladeFPMap.key * 'a -> ('b * 'c) All_sets.IntegerMap.t)
              (map : 'a Tree.CladeFPMap.t) : 'b =
    let sets =
        Tree.CladeFPMap.fold
            (fun set cnt lst ->
                if cnt >= majority_cutoff then (set, cnt) :: lst
                else lst)
            map
            []
    in
    let sets =
        List.sort
            (fun (x, _) (y, _) ->
                (All_sets.Integers.cardinal x) - (All_sets.Integers.cardinal y))
            sets
    in
    let trees = List.fold_left builder All_sets.IntegerMap.empty sets in
    let tree, _ = All_sets.IntegerMap.find !coder trees in
    tree

let consensus is_collapsable to_string maj trees root =
    let number_of_trees = float_of_int (List.length trees) in
    let print_frequency = maj <> number_of_trees 
    and coder = ref 0 in
    let tree_builder = build_a_tree to_string number_of_trees print_frequency coder in
    trees --> List.map 
                (fun x ->
                    let y = get_parent root x in
                    Tree.reroot (root, y) x.tree, is_collapsable x)
          --> List.fold_left
                (fun acc (x, y) -> add_tree_to_counters y acc x)
                Tree.CladeFPMap.empty
          --> Tree.CladeFPMap.map (float_of_int)
          --> make_tree maj coder tree_builder


let preprocessed_consensus to_string (maj : float) num_trees map =
    let coder = ref 0 in
    let tree_builder = build_a_tree to_string (float_of_int num_trees) true coder in
    let map = Tree.CladeFPMap.map (float_of_int) map in
    make_tree maj coder tree_builder map

let extract_counters sets set =
    Tree.CladeFPMap.fold (fun a b acc ->
        let freq = 
            try Tree.CladeFPMap.find a sets with
            | Not_found -> 0
        in
        Tree.CladeFPMap.add a freq acc ) 
    set
    Tree.CladeFPMap.empty

let generic_supports generate_tree_sets to_string maj number_of_samples tree sets =
    let coder = ref 0 in
    let tree_builder = 
        build_a_tree to_string number_of_samples true coder
    in
    tree --> generate_tree_sets
         --> extract_counters sets
         --> Tree.CladeFPMap.map (float_of_int)
         --> make_tree maj coder tree_builder

let supports to_string maj number_of_samples tree sets =
    generic_supports (add_tree_to_counters (fun _ _ -> false) Tree.CladeFPMap.empty)
                     to_string maj number_of_samples tree sets

let support_of_input to_string maj number_of_samples tree data sets = 
    let creating_counters lst = 
        List.fold_left (fun acc x ->
            snd (make_tree_counters (fun x -> Data.taxon_code x data) acc x)) 
        Tree.CladeFPMap.empty lst
    in
    generic_supports creating_counters to_string maj number_of_samples tree sets

(* A function that returns the bremer support tree based on the set of (costs, 
* tree) of sets, for the input tree *)
let bremer to_string (cost : float) tree generator files =
    let tree_file_handlers = ref (List.map (Tree.Parse.stream_of_file true) files) in
    (* We first create a function that takes a map of clades and best cost found
    * for a tree _not_ containing the set, and a set of clades belonging to a
    * tree, with it's associated cost, and update the map according to the cost
    * for the set of clades, only if better. *)
    let number_of_leaves = List.length (Tree.get_all_leaves tree) in
    let replace_when_smaller map =
        let map = ref map in
        let cntr = ref 1 in
        let status = Status.create "Bremer Estimation" None "Comparing tree with trees in file" in
        while [] <> !tree_file_handlers do
            match !tree_file_handlers with
            | (tree_generator, close_tree_generator) :: t ->
                tree_file_handlers := t;
                (try while true do
                    try Status.full_report ~adv:!cntr status;
                        let input_tree = tree_generator () in
                        let new_cost, sets = generator input_tree in
                        map :=
                            Tree.CladeFPMap.fold
                                (fun my_clade best_cost acc ->
                                    let len =  All_sets.Integers.cardinal my_clade in
                                    if len < 2 || len = number_of_leaves then
                                        acc
                                    else if (not (Tree.CladeFP.CladeSet.mem my_clade sets)) &&
                                            ((new_cost -. cost) < best_cost) then
                                        Tree.CladeFPMap.add my_clade (new_cost -. cost) acc
                                    else
                                        acc)
                                !map
                                !map;
                        incr cntr;
                    with | End_of_file as err -> raise err 
                         | _ -> ()
                    done;
                    close_tree_generator ();
                with | End_of_file -> 
                    close_tree_generator ();
                    Status.finished status)
            | [] -> ()
        done;
        !map
    in
    (** We create a map with all the sets of clades in the input tree *)
    let map : float Tree.CladeFPMap.t =
        let map = add_tree_to_counters (fun _ _ -> false) Tree.CladeFPMap.empty tree in
        Tree.CladeFPMap.map (fun _ -> infinity) map
    in
    (* We now update that map with the best length found for each tree not
    * having the clade *)
    let coder = ref 0 in
    let res = replace_when_smaller map in
    let tree_builder = build_a_tree to_string 1. true coder in
    let res = make_tree neg_infinity coder tree_builder res in
    res
