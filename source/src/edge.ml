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

let () = SadmanOutput.register "Edge" "$Revision$"

exception IllegalEdgeConversion

module type EdgeSig = sig
    (** The type of the edge data *)
    type e
    (** The type of a node *)
    type n
    (** Weather or not an edge holds data (false when e = unit), or the edge
    * type is not to be used *)
    val has_information : bool
    (* Calculate the median between the nodes *)
    (*
    val calculate : n -> n -> e
    *)

    (* Convert the contents of an edge into a node (if it is possible). If it is
    * not possible due to the nature of the edge information, raise
    * IllegalEdgeConversion *)
    val to_node : int -> (int * int) -> e -> n
    val of_node : int option -> n -> e
    val recode : (int -> int) -> e -> e
    val force : e -> e
end

module Edge : EdgeSig with type e = unit with type n = Node.node_data = struct
    type e = unit
    type n = Node.node_data
    let has_information = false
    let calculate _ x = ()
    let of_node _ n = ()
    let to_node _ _ e = failwith "Impossible"
    let recode a b = failwith "Impossible"
    let force x = x
end

module SelfEdge : EdgeSig with type e = Node.node_data with type n = Node.node_data
= struct
    type e = Node.node_data
    type n = Node.node_data
    let has_information = false
    let calculate _ x = x
    let of_node _ n = n
    let to_node _ _ e = e
    let recode a b = Node.Standard.recode a b
    let force x = x
end


(*
module SuperRoot (Node : NodeSig.S) : 
    EdgeSig with type e = Node.n with type n = Node.n = struct

        type e = Node.n
        type n = Node.n
        let has_information = true
        let calculate = Node.median None
        let to_node x = x

    end

module LazyRoot (Node : NodeSig.S) :
    EdgeSig with type e = Node.n Lazy.t with type n = Node.n = struct

        type e = Node.n Lazy.t
        type n = Node.n
        let has_information = true
        let calculate a b = Lazy.from_fun (fun () -> Node.median None a b)
        let to_node x = Lazy.force x

    end
*)
module LazyEdge : EdgeSig with type e = AllDirNode.OneDirF.n with type n =
    AllDirNode.AllDirF.n = struct
        type e = AllDirNode.OneDirF.n
        type n = AllDirNode.AllDirF.n
        let has_information = true
        let to_node code dir e = 
            let res = { AllDirNode.lazy_node = e; dir = Some dir; code = code}
            in
            { AllDirNode.unadjusted = [res]; adjusted = Some res }
        let of_node a b = 
            match a with
            | Some a -> (AllDirNode.not_with a b.AllDirNode.unadjusted).AllDirNode.lazy_node
            | None ->
                    match b.AllDirNode.unadjusted with
                    | [x] -> x.AllDirNode.lazy_node
                    | _ -> failwith "Edge.LazyEdge.of_node"
        let recode a b = AllDirNode.OneDirF.recode a b
        let force x = AllDirNode.OneDirF.force x
    end

