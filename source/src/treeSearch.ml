(* POY 5.1.1. A phylogenetic analysis program using Dynamic Homologies.       *)
(* Copyright (C) 2011  Andr�s Var�n, Lin Hong, Nicholas Lucaroni, Ward Wheeler*)
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

(** [TreeSearch] contains high-level functions to perform tree searches *) 
let () = SadmanOutput.register "TreeSearch" "$Revision$"

let debug_find_local_optimum = false

let has_something something (`LocalOptimum (cost_calculation)) =
    let cost_calculation = cost_calculation.Methods.cc in
    List.exists (fun x -> x = something) cost_calculation

module type S = sig

    type a
    type b

    val process_trees :
        Methods.information_contained list -> (a, b) Ptree.p_tree Sexpr.t
            -> (string option * Tree.Parse.tree_types) list *
                (string * string, (int array * float option) list) Hashtbl.t

    val report_trees :
        Methods.information_contained list -> string option ->  (a, b) Ptree.p_tree Sexpr.t -> unit

    val forest_break_search_tree :
        (a, b) Ptree.nodes_manager option ->  float -> (a, b) Ptree.p_tree -> (a, b) Ptree.p_tree

    val diagnose :
        (a, b) Ptree.p_tree -> (a, b) Ptree.p_tree

    val find_local_optimum :
        ?base_sampler:(a, b) Sampler.search_manager_sampler -> 
        ?queue : (float array * (int * int) list * int * Status.status * int ref * float) ->
        Data.d ->
            Sampler.ft_queue ->
                (a, b) Ptree.p_tree Sexpr.t ->
                    All_sets.IntSet.t Lazy.t ->
                        Methods.local_optimum -> (a, b) Ptree.p_tree Sexpr.t

      val forest_search :
          Data.d ->
              Sampler.ft_queue ->
                  float ->
                      Methods.local_optimum ->
                          (a, b) Ptree.p_tree
                          Sexpr.t ->
                              (a, b) Ptree.p_tree Sexpr.t

      val fusing :
          Data.d ->
              Sampler.ft_queue ->
                  (a, b) Ptree.p_tree Sexpr.t ->
                      int option * int option * Methods.tree_weights * 
                      'a * Methods.local_optimum *
                      (int * int) -> (a, b) Ptree.p_tree Sexpr.t

        val output_consensus :
            Data.d -> (a, b) Ptree.p_tree Sexpr.t ->
                string option -> float option -> bool -> unit
    end

let get_transformations (`LocalOptimum (l_opt)) = 
    let clist = l_opt.Methods.cc in
    let remover meth acc =
        match meth with
        | #Methods.transform as x -> x :: acc
    in 
    List.fold_right remover clist []

let sets_of_consensus trees  = 
    Lazy.from_fun 
    (fun () ->
        let len = Sexpr.length trees 
        and trees = 
            Sexpr.fold_left 
            (fun acc x -> x.Ptree.tree :: acc)
            []
            trees 
        in
        let counters = 
            List.fold_left
            (Ptree.add_tree_to_counters (fun _ _ -> false))
            Tree.CladeFPMap.empty
            trees
        in
        Tree.CladeFPMap.fold 
        (fun set cnt acc ->
            if cnt = len then All_sets.IntSet.add set acc
            else acc)
        counters
        All_sets.IntSet.empty)

let sets_of_parser data tree =
    let get_code x =
        try Data.taxon_code x data
        with Failure s -> raise (Failure (s^" in constraint file."))
    in
    let rec process tree acc =
        match tree with
        | Tree.Parse.Leafp x ->
                let res = All_sets.Integers.singleton (get_code x) in
                All_sets.IntSet.add res acc, res
        | Tree.Parse.Nodep (chld, _) ->
                let acc, lst = List.fold_left (fun (acc, res) x ->
                    let a, b = process x acc in
                    a, (b :: res)) (acc, []) chld
                in
                let union =
                    List.fold_left All_sets.Integers.union
                    All_sets.Integers.empty lst
                in
                All_sets.IntSet.add union acc, union
    in
    fst (process (Tree.Parse.strip_tree tree) All_sets.IntSet.empty)

let sets meth data trees = 
    let process_constraints options = 
        List.fold_left 
            (fun acc x -> match x with
                | `ConstraintFile file -> Some file
                | _ -> acc) 
            None options
    in
    match meth with
    | `Partition options -> 
        begin match process_constraints options with
            | None -> sets_of_consensus trees
            | Some filename ->
                try match Tree.Parse.of_file filename with
                | [[tree]] -> lazy (sets_of_parser data tree)
                | _ ->
                    Status.user_message Status.Error
                        ("To@ use@ constraint@ files@ you@ must@ provide@ a@ " ^
                         "single@ tree,@ not@ more,@ no@ forests@ are@ allowed.");
                    failwith "Illegal input file"
                with
                   | err -> Status.user_message Status.Error
                                "Error@ reading@ constraint@ file";
                            raise err
        end
    | _ -> lazy (All_sets.IntSet.empty)

let search_time_and_trees_considered a b = 
    [ ("search-time", string_of_float a); ("trees-considered", string_of_int b)]

module MakeNormal
    (Node : NodeSig.S) 
    (Edge : Edge.EdgeSig with type n = Node.n) 
    (TreeOps : 
            Ptree.Tree_Operations with 
            type a = Node.n with type b = Edge.e) = struct

    module PtreeSearch = Ptree.Search (Node) (Edge) (TreeOps)
    module SamplerApp = Sampler.MakeApp (Node) (Edge)
    module SamplerRes = Sampler.MakeRes (Node) (Edge) (TreeOps)
    module PhyloQueues = Queues.Make (Node) (Edge)
    module PhyloTabus = Tabus.Make (Node) (Edge)

    type a = Node.n
    type b = Edge.e

    let odebug = Status.user_message Status.Information

    let simplified_report_trees compress filename data (tree, cost, _) =
        let fo = 
            let lst = if compress then [StatusCommon.Compress] else [] in
            Status.Output (filename, false, lst) 
        in
        let output tree = 
            let cost = string_of_float cost in
            let tree = 
                PtreeSearch.build_trees 
                    tree
                    (fun x -> Data.code_taxon x data) 
                    (fun _ _ _ _ -> None)
                    (fun _ _ -> "")
                    (fun _ _ -> false)
                    None
                    None
                    (fun _ -> "")
            in
            let output (_,tree) =
                Status.user_message fo "@[";
                Status.user_message fo 
                (AsciiTree.for_formatter false true true tree);
                Status.user_message fo ("[" ^ cost ^ "]");
                Status.user_message fo "@]@,"
            in
            List.iter output tree
        in
        Status.user_message fo "@[<v>";
        output tree;
        Status.user_message fo "@]";
        Status.user_message fo "%!"

    let characters_designation (c:Data.bool_characters) (d:Data.d) =
        List.map (function
                    | [] -> None
                    | xs -> Some (Array.of_list xs))
                 (Data.categorize_characters_comp d c)

    let report_trees_and_branches compress filename chars branches ptree : unit =
        let fo =
            let lst = if compress then [StatusCommon.Compress] else [] in
            Status.Output (filename, false, lst)
        and trees =
            List.fold_left
                (fun acc chars ->
                    let additional_trees = 
                        PtreeSearch.build_trees
                            ptree.Ptree.tree
                            (fun x -> Data.code_taxon x ptree.Ptree.data)
                            (fun _ _ _ _ -> None)
                            (fun _ _ -> "")
                            (fun _ _ -> false)
                            (Some branches)
                            chars
                            (function _ -> "")
                    in
                    additional_trees @ acc)
                []
                (characters_designation chars ptree.Ptree.data)
        in
        let adj_cost = string_of_float (Ptree.get_cost `Adjusted ptree) in
        Status.user_message fo "@[<v>";
        List.iter
            (fun (_,x) ->
                Status.user_message fo "@[";
                Status.user_message fo (AsciiTree.for_formatter false true true x);
                Status.user_message fo ("[" ^ adj_cost ^ "]");
                Status.user_message fo "@]@,")
            trees;
        Status.user_message fo "@]%!"


    let process_trees ic trees =
        let branches =
            List.fold_left
                (fun acc -> function | `Branches x -> true,x | _ -> acc)
                (false,None) 
                ic
        in
        let collapse =
            List.fold_left
                (fun acc -> function | `Collapse x -> x | _ -> acc) None ic
        in
        let labeling = Hashtbl.create 1371 in
        let node_labeling =
            let names_idx = ref 0 in
            (fun tree_name x y chars ->
                let node_name = "poy_"^string_of_int !names_idx in
                incr names_idx;
                Hashtbl.add labeling (tree_name,node_name) chars;
                Some ("&"^node_name))
        and tree_labeling =
            let tree_idx = ref ~-1 in
            (fun topo handle ->
                let prefix = match topo.Tree.tree_name with
                    | Some x -> x
                    | None   -> incr tree_idx;
                                "tree" ^ string_of_int !tree_idx
                in match Tree.handle_list topo with
                    | [x]-> assert( handle = x );
                            prefix
                    | [] -> assert false;
                    | _  -> prefix ^ "_" ^ string_of_int handle)
        in
        let output =
            (fun acc tree ->
                let cost = string_of_float (Ptree.get_cost `Adjusted tree) in
                let tree =
                    PtreeSearch.build_forest_with_names_n_costs_n_branches
                        collapse tree cost node_labeling tree_labeling branches None
                in
                tree @ acc)
        in
        Sexpr.fold_left output [] trees, labeling


    let report_trees ic filename trees =
        (* test characteristics to print from `ic` variable *)
        let leaf_only = not (List.exists (function `Cost -> true | _ -> false) ic) in
        let hennig_style = List.exists (function `HennigStyle -> true | _ -> false) ic in
        let nexus_style = List.exists (function `NexusStyle -> true | _ -> false) ic in
        let tree_len = List.exists (function `Total -> true | _ -> false) ic in
        let newline = if hennig_style then "" else "@\n" in
        let ic = if hennig_style then (`Margin (1000000010 - 1)) :: ic else ic in
        let branches : bool * Methods.report_branch option =
            List.fold_left
                (fun acc -> function | `Branches x -> true,x | _ -> acc)
                (false,None) 
                ic
        in
        let collapse =
            List.fold_left
                (fun acc -> function | `Collapse x -> x | _ -> acc) None ic
        in
        let ori_margin = StatusCommon.Files.get_margin filename in
        let fo_ls = ref [] in 
        let fo = Status.user_message (Status.Output (filename, false, !fo_ls)) in
        let () =
            try match List.find (function `Margin _ -> true | _ -> false) ic with
                | `Margin m ->
                    fo_ls := (StatusCommon.Margin m)::!fo_ls;
                    StatusCommon.Files.set_margin filename m
                | _ -> assert false
            with | Not_found -> ()
        in
        let get_chars data =
            try match List.find (function `Chars _ -> true | _ -> false) ic with
                | `Chars x -> characters_designation x data
                | _        -> assert false
            with Not_found -> characters_designation `All data
        in
        (* print all trees from sexpr *)
        let output =
            let is_first = ref true in
            (fun tree ->
                let cost = string_of_float (Ptree.get_cost `Adjusted tree) in
                let chars= get_chars tree.Ptree.data in
                let tree =
                    List.fold_left
                        (fun acc c ->
                            let ts =
                                PtreeSearch.build_forest_with_names_n_costs
                                                collapse tree cost branches c
                            in
                            ts @ acc)
                        []
                        chars
                in
                let output cnt tree =
                    if hennig_style then
                        if not !is_first then fo " * "
                        else is_first := false
                    else if nexus_style then
                        fo ("TREE POY" ^ string_of_int cnt ^ " = ");
                    fo "@[";
                    fo (AsciiTree.for_formatter (not hennig_style ) (not hennig_style) leaf_only tree);
                    if leaf_only && tree_len then fo ("[" ^ cost ^ "]"); 
                    if not hennig_style then fo ";" else fo "@?";
                    fo "@]";
                    fo newline;
                    cnt + 1
                in
                ignore (List.fold_left output 0 tree))
        in
        fo (if hennig_style then "@[<h>" else if nexus_style then "@[<v>" else "");
        fo (if hennig_style then "tread " else if nexus_style then "@[BEGIN TREES;@]@." else "");
        Sexpr.leaf_iter (output) trees;
        fo (if hennig_style then ";" else if nexus_style then "@[END;@]@." else "");
        fo (if hennig_style then  "@]" else if nexus_style then "@]@\n" else "");
        fo "@\n%!";
        StatusCommon.Files.set_margin filename ori_margin


    let get_search_function tabu_creator trajectory meth =
        let stepfn = function
            | `Spr -> PtreeSearch.spr_step, "SPR"
            | `Tbr -> PtreeSearch.tbr_step, "TBR"
        in
            match trajectory with
            | `AllThenChoose ->
                    (match meth with
                    | `Alternate _ -> 
                            PtreeSearch.alternate
                            (PtreeSearch.repeat_until_no_more tabu_creator 
                            (PtreeSearch.search true (stepfn `Spr)))
                            (PtreeSearch.search_local_next_best (stepfn `Tbr))
                    | `SingleNeighborhood x -> 
                            PtreeSearch.repeat_until_no_more tabu_creator
                            (PtreeSearch.search_local_next_best (stepfn x))
                    | `ChainNeighborhoods x -> 
                            PtreeSearch.repeat_until_no_more tabu_creator
                            (PtreeSearch.search false (stepfn x))
                    | `None -> (fun a -> a))
            | _ ->
                    (match meth with
                    | `Alternate _ -> 
                            PtreeSearch.alternate
                            (PtreeSearch.search true (stepfn `Spr))
                            (PtreeSearch.search_local_next_best (stepfn `Tbr))
                    | `SingleNeighborhood x -> 
                            PtreeSearch.search_local_next_best (stepfn x)
                    | `ChainNeighborhoods x -> 
                            PtreeSearch.search false (stepfn x)
                    | `None -> (fun a -> a))

    (** [forest_break_search_tree origin_cost tree] attempts to break all edges
        in [tree] with length greater than [origin_cost].  It attempts to be
        liberal about breaking edges---it may break more edges than is strictly
        correct.  However, this is fine for the forest searching algorithm.

        Note that in our trees, weights are on nodes rather than edges; thus,
        what we actually do is check the median cost at each node, and then, for
        candidate nodes, we pick the best of its edges to break.
    *)
    let forest_break_search_tree adj_mgr origin_cost tree =
        (** [break edge tree] breaks an edge in the tree and updates the tree data
            accordingly *)
        let break edge tree =
            let Tree.Edge(bfrom, bto) = edge in
            let breakage = TreeOps.break_fn adj_mgr (bfrom, bto) tree in
            TreeOps.uppass breakage.Ptree.ptree 
        in
        let tree = Ptree.set_origin_cost origin_cost tree in
        (* Iterate over all the edges, possibly breaking... *)
        let tree = 
            Tree.EdgeMap.fold
            (fun edge _ tree ->
                try
                    let cost = Ptree.get_cost `Adjusted tree in
                    let new_tree = break edge tree in
                    let new_cost = Ptree.get_cost `Adjusted new_tree in
                    if new_cost < cost then new_tree else tree
                with _ -> tree)
            tree.Ptree.edge_data tree in
        (* (TODO: also check the roots for breaking!!) *)
        tree

    (** [forest_joins forest] attempts to join pairs of forest components using
        TBR join. Those whose join cost is less than the origin/loss cost will
        be kept.
        TODO:: To get the forest search working again, we need to modify the
        tabu managers so that instead of using left and right uses a code
        assigned to each individual component. That's the only way to get the
        necessary way to connect multiple elements in a forest using the tabu
        managers. Right now there is no nice way to do it, and this is a low
        priority issue, therefore, I am leaving a note and doing it later. *)
    let rec forest_joins forest = forest
        (*let components = Ptree.components forest in
        let join_tabu = PhyloTabus.join_to_tree_in_forest forest in 
        let status = Status.create "Attempting to join forest components"
                                   (Some components) ""
        in
        (* [tbr_joins comp] tries to join [comp] to all other components *)
        let tbr_joins component = 

            let tabu, right = join_tabu component in
            let mgr = new PhyloQueues.first_best_srch_mgr (new Sampler.do_nothing) in
            let () = mgr#init [(forest, Ptree.get_cost `Adjusted forest, Ptree.NoCost, tabu)] in
            (* get the current `Right junction *)
            let j2 = Ptree.jxn_of_handle forest right in
            (* get the `Right (clade) root node *)
            let clade_node =
                let root =
                    All_sets.IntegerMap.find right forest.Ptree.component_root in
                let root = root.Ptree.root_median in
                match root with
                | None -> assert false
                | Some (_, clade_node) -> clade_node in
            let status = PtreeSearch.tbr_join mgr tabu forest j2 clade_node
                                              forest.Ptree.origin_cost
            in
            match status with
            | Tree.Break ->
                let results = mgr#results in
                (* Only interested in the first one *)
                let (forest, _, _) = List.hd results in
                Some forest
            | Tree.Continue
            | Tree.Skip -> None 
        in
        let rec try_comp component =
            if component = components then
                None
            else
                match tbr_joins component with
                | None -> try_comp (succ component)
                | Some forest -> Some forest
        in
        Status.finished status;
        match res with
        | None -> forest
        | Some forest -> forest_joins forest *)

    let diagnose tree =
        PtreeSearch.uppass (PtreeSearch.downpass tree)

    let queue_manager max th keep sampler =
        fun () ->
            match max, th with
            | 1, th -> (*ignore threshold in this case*)
                    if th <> 0. then
                    Status.user_message Status.Information 
                    ("threshold@ is@ ignored@ because@ tree@ number@ is@ 1.");
                    new PhyloQueues.first_best_srch_mgr (sampler ())
            | n, th -> 
                    new PhyloQueues.hold_n_threshold_srch_mgr n keep th (sampler ())

    let create_sampler data queue previous item adj_tabu = 
        let ob = 
            match item with
            | `PrintTrajectory filename -> 
                  (new SamplerApp.print_next_tree 
                  (simplified_report_trees false filename data))
            | `KeepBestTrees ->
                    (new SamplerApp.local_optimum_holder queue)
            | `MaxTreesEvaluated trees ->
                    (new SamplerApp.counted_cancellation trees) 
            | `TimeOut time ->
                    (new SamplerApp.timed_cancellation time) 
            | `TimedPrint (time, filename) ->
                    (new SamplerApp.timed_printout queue time 
                     (simplified_report_trees false filename data))
            | `UnionStats (filename, depth) ->
                    new SamplerRes.union_table depth
                    (Status.user_message (Status.Output (filename, false, [])))
            | `RootUnionDistr filename ->
                    Status.user_message Status.Error 
                    ("Sorry@ the@ root@ union@ distribution@ sampler@ is@ "
                    ^ "currently@ unsupported");
                    new Sampler.do_nothing 
                    (* TODO: This sampler is off for now *)
(*                    new SamplerRes.union_root_distribution *)
(*                    (Status.user_message (Status.Output (filename, false)))*)
            | `AttemptsDistr filename ->
                    new SamplerRes.tests_before_next 
                    (Status.user_message (Status.Output (filename, false, [])))
            | `BreakVsJoin filename ->
                    new SamplerRes.break_n_join_distances 
                    (Status.user_message (Status.Output (filename, false, [])))
            | `LikelihoodModel filename ->
                    new SamplerRes.likelihood_model_iteration
                        (Status.user_message (Status.Output (filename, false, [])))
            | `Likelihood filename ->
                    let do_compress = None <> filename in
                    new SamplerRes.likelihood_verification
                        (Status.user_message (Status.Output (filename, false, [])))
                        (report_trees_and_branches do_compress filename `All)
            | `AllVisited filename ->
                    let join_fn incr a b c = 
                        let a, _ = TreeOps.join_fn (Some adj_tabu) incr a b c in
                        a
                    in
                    let do_compress = None <> filename in
                    (new SamplerApp.visited join_fn 
                        (simplified_report_trees do_compress filename data))
        in
        new Sampler.composer previous ob

    let create_adjust_manager = function
        | `LocalOptimum l_opt ->
            let m, b = l_opt.Methods.tabu_iterate in
            let thrsh = match m with 
                | `Threshold f 
                | `Both (f,_)  -> Some f
                | `Always      -> Some 0.0
                | `Null 
                | `MaxCount _  -> None
            and count =  match m with
                | `MaxCount m 
                | `Both (_,m)  -> Some m
                | `Always      -> Some 0
                | `Null 
                | `Threshold _ -> None
            in
            match b with
            | `Null           -> PhyloTabus.simple_nm_none count thrsh
            | `AllBranches    -> PhyloTabus.simple_nm_all count thrsh
            | `JoinDelta      -> PhyloTabus.complex_nm_delta count thrsh
            | `Neighborhood x -> PhyloTabus.complex_nm_neighborhood x count thrsh

    let sampler meth sampler data queue lst () =
        let sampler = 
            match sampler with
            | Some x -> x
            | None -> new Sampler.do_nothing
        and adj_tabu = create_adjust_manager meth in
        List.fold_left 
        (fun prev item -> create_sampler data queue prev item adj_tabu) 
        sampler
        lst

let rec find_local_optimum ?base_sampler ?queue data emergency_queue
        (trees : (a, b) Ptree.p_tree Sexpr.t)
        (sets :   All_sets.IntSet.t Lazy.t)
        (meth : Methods.local_optimum) :
    (a, b) Ptree.p_tree Sexpr.t =
    let trees = Sexpr.map TreeOps.unadjust trees in
    let local_search_results_reporting lst =
        let builder (acc, cnt) (_, cost) =
            let hd = 
                ("tree_" ^ string_of_int cnt ^ 
                "_cost", string_of_float cost) 
            in
            hd :: acc, cnt + 1
        in
        let acc, _ = 
            Sexpr.fold_left 
            (fun acc x -> List.fold_left builder acc x) 
            ([], 0) 
            lst 
        in
        acc
    in

    (* let `LocalOptimum
            (search_space, th, max, keep, cost_calculation, origin, 
            trajectory, break_tabu, join_tabu, reroot_tabu, nodes_tabu, samples)
            = meth in *)
    let `LocalOptimum (l_opt) = meth in
    let samplerf = sampler meth base_sampler data emergency_queue l_opt.Methods.samples in
    let sets =
        try
            match l_opt.Methods.tabu_join with
            | `Partition opts -> 
                    (match 
                        List.find (function `Sets _ -> true | _ -> false)
                        opts
                    with
                    | `Sets x -> x
                    | _ -> assert false)
            | _ -> sets
        with
        | Not_found -> sets
    in
    let queue_manager =
        match queue with
        | Some
            (best_vals, node_indices, starting, status, nbhood_count,
            orig_cost) -> 
                (fun () -> new PhyloQueues.supports_manager best_vals node_indices 
                starting status nbhood_count orig_cost (new Sampler.do_nothing))
        | None ->
                match l_opt.Methods.tm with (* trajectory *)
                | `AllAround f -> 
                        (fun () -> new PhyloQueues.all_possible_joins f
                        (samplerf ()))
                | `BestFirst ->
                            queue_manager l_opt.Methods.num_keep
                            l_opt.Methods.threshold l_opt.Methods.keep samplerf
                | `AllThenChoose -> 
                        fun () -> 
                            new PhyloQueues.all_neighbors_srch_mgr
                            TreeOps.join_fn TreeOps.break_fn TreeOps.reroot_fn 
                            TreeOps.incremental_uppass
                            (samplerf ())
                | `Annealing (a, b) -> 
                        fun () ->
                            new PhyloQueues.annealing_srch_mgr 1 `Last 0.0 a b
                            (samplerf ())
                | `PoyDrifting (a, b) -> 
                        fun () ->
                            new PhyloQueues.classic_poy_drifting_srch_mgr 1 `Last
                            a b (samplerf ())
    in
    let partition_for_other_tabus =
        match l_opt.Methods.tabu_join with
        | `Partition _ -> 
                Some (`Sets (Lazy.force sets))
                (* TMP
                Some (`Height 2)
                *)
        | _ -> None
    in
    let tabu_manager ptree = 
        let get_depth = function
            | None -> max_int 
            | Some v -> v
        in
        let breakfn =
          let running_parallel,n,p =
            IFDEF USEPARALLEL THEN
              true,(Mpi.comm_size Mpi.comm_world),(Mpi.comm_rank Mpi.comm_world)
            ELSE
              false,1,0
            END
          in
            if l_opt.Methods.parallel && running_parallel then
              match l_opt.Methods.tabu_break with
              | `Randomized -> PhyloTabus.random_break_par n p
              | `DistanceSorted e -> PhyloTabus.sorted_break_par n p e partition_for_other_tabus
              | `OnlyOnce -> PhyloTabus.only_once_break_par n p
            else
              match l_opt.Methods.tabu_break with
              | `Randomized -> PhyloTabus.random_break
              | `DistanceSorted e -> PhyloTabus.sorted_break e partition_for_other_tabus
              | `OnlyOnce -> PhyloTabus.only_once_break
        in
        let joinfn = match l_opt.Methods.tabu_join with
            | `UnionBased depth ->
                    PhyloTabus.union_join (get_depth depth)
            | `AllBased depth -> 
                    PhyloTabus.distance_join (get_depth depth)
            | `Partition options ->
                    let depth = 
                        List.fold_left
                          (fun acc -> function
                            | `MaxDepth x -> Some x
                            | _ -> acc)
                        None options
                    in
                    PhyloTabus.partitioned_join (`Sets (Lazy.force sets)) 
                                                (get_depth depth)
        in
        let iterfn = create_adjust_manager meth in
        let rerootfn =
            match l_opt.Methods.tabu_reroot with
            | `Bfs depth ->
                    PhyloTabus.reroot partition_for_other_tabus (get_depth depth)
        in
        new PhyloTabus.standard_tabu ptree joinfn rerootfn breakfn iterfn
    in
    let search_fn = get_search_function tabu_manager l_opt.Methods.tm l_opt.Methods.ss in
    let search_features =
            PtreeSearch.features meth ((queue_manager ())#features
            (* TODO: tabu features *)
            (([])))
    in
    Sadman.start "search" search_features;
    let timer = Timer.start () in
    let result = 
            PhyloQueues.reset_trees_considered ();
            let process_tree tree = 
                let cost = Ptree.get_cost `Adjusted tree in
                let tabu_manager = tabu_manager tree in
                let queue_manager = queue_manager () in
                let uncost = Ptree.get_cost `Unadjusted tree in
                if debug_find_local_optimum then 
                    Printf.printf "init tree search with cost = adj:%f(unadj:%f)\n%!" cost uncost;
                queue_manager#init [(tree, cost, Ptree.NoCost, tabu_manager)];
                try
                    let res = (search_fn queue_manager)#results in
                    List.map (fun (a, _, _) ->
                        if a.Ptree.tree <> tree.Ptree.tree then
                            let a = PtreeSearch.uppass a in
                            if debug_find_local_optimum then
                                Printf.printf "new tree with cost = %f\n%!" (Ptree.get_cost `Adjusted a);
                            (a, Ptree.get_cost `Adjusted a)
                        else
                            let _ = 
                                if debug_find_local_optimum then
                                Printf.printf "same old tree with cost %f\n%!" (Ptree.get_cost `Adjusted a) 
                            in
                            (a, Ptree.get_cost `Adjusted a)
                    ) res
                with
                | Methods.TimedOut -> [(tree, Ptree.get_cost `Adjusted tree)]
            in
            Sexpr.map_status "Tree search" process_tree trees 
    in
    let time = Timer.get_user timer in
    let trees_considered = PhyloQueues.get_trees_considered () in
    let sadman_results = local_search_results_reporting result in
    Sadman.finish 
        (search_time_and_trees_considered time trees_considered @
            sadman_results);
    Sexpr.map_insexpr (List.map (fun (a, _) -> `Single a)) result


let forest_search data queue origin_cost search trees =
    (* Forest search happens in three steps.  First, we find candidate high-cost
       medians for breaking.  Once those are broken, we search on the entire
       forest of trees.  We then attempt to TBR join to improve our overall
       score... *)
    let adj_mgr = Some (create_adjust_manager search) in
    let trees =
        Sexpr.map_status "Breaking trees"
            (forest_break_search_tree adj_mgr origin_cost)
            trees in
    let trees = 
        let `LocalOptimum s = search in
        find_local_optimum data queue trees 
        (sets s.Methods.tabu_join data trees) search
    in 
    (* TBR joins *)
    let trees = Sexpr.map_status "TBR joining trees" forest_joins trees in
    Sexpr.leaf_iter
        (fun trees ->
            let cost = Ptree.get_cost `Adjusted trees in
            Status.user_message Status.Information
                ("Forest search found forest with "
                ^ string_of_int (Ptree.components trees)
                ^ " components and cost " ^ string_of_float cost))
        trees;
    let trees = Sexpr.map (Ptree.set_origin_cost 0.) trees in 
    trees


    (** [fusing trees params] performs tree fusing with the given parameters *)
    let fusing data queue trees
        (iterations, max_trees, weighting, keep_method, local_optimum, (min,max)) =
        (* default max_trees to number of trees *)
        let max_trees = match max_trees with
            | Some m -> m
            | None -> Sexpr.cardinal trees
        in
        (* default iterations to....... 4 * max_trees ?? *)
        let iterations = match iterations with
            | Some i -> i
            | None -> max_trees * 4
        in
        Sadman.start "tree-fusing"
            [("iterations", string_of_int iterations);
             ("max_trees", string_of_int max_trees); ];
        let weighting = match weighting with
            | `Uniform -> (fun _ -> 1.)
        in
        let keep_method = `Best in
        let max_code, cntr = 
            All_sets.IntegerMap.fold
                (fun code _ (acc, cnt) -> 
                    Pervasives.max code acc, cnt + 1)
                data.Data.taxon_codes
                (0, 0)
        in
        let process t =
            Sexpr.to_list
                (find_local_optimum data queue (Sexpr.singleton t)
                                    (sets_of_consensus trees) local_optimum)
        in
        let tree_list_with_nodes_managers =
            List.map
                (fun x -> x,create_adjust_manager local_optimum)
                (Sexpr.to_list trees)
        in
        let trees =
            PtreeSearch.fuse_generations
                tree_list_with_nodes_managers
                max_code
                max_trees
                weighting
                keep_method
                iterations
                process
                (min, Pervasives.min (cntr - 3) max)
        in
        Sadman.finish [];
        Sexpr.of_list trees

    let output_consensus data trees filename v graphic = 
        (* We will use a negative number for the root code to avoid
        * any clash *)
        let ntrees = Sexpr.length trees in
        let majority, majority_text = 
            match v with
            | None ->
                (float_of_int ntrees), "Strict"
            | Some v when v > 100.0 -> 
                Status.user_message Status.Error 
                    ("You@ have@ requested@ a@ consensus@ with@ majority@ "
                    ^"rule@ of@ more@ than@ 100@ percent,@ I@ don't@ see@ how@ "
                    ^"to@ do@ that.");
                failwith "Illegal Consensus Parameter";
            | Some v when v <= 50.0 -> 
                Status.user_message Status.Error 
                    ("You@ have@ requested@ a@ consensus@ with@ majority@ rule"
                    ^"@ less@ than@ or@ equal@ to@ 50@ percent;@ I@ can@ not@ "
                    ^"do@ that@ because@ that@ percentage@ is@ not@ a@ "
                    ^"majority!.@ Either@ you@ made@ a@ typo@ or@ you@ should@ "
                    ^"reconsider@ your@ parameter@ selection.");
                failwith "Illegal Consensus Parameter";
            | Some v -> 
                (ceil ((v *. (float_of_int ntrees) /. 100.0))), ((string_of_float v) ^ " percent")
        in
        let lst_trees = Sexpr.to_list trees in
        let rooting_leaf, tree = match data.Data.root_at with
            | Some v -> 
                begin match lst_trees with
                    | hd :: _ -> v, hd
                    | _ -> failwith "No trees in memory"
                end
            | None ->
                begin match lst_trees with
                    | hd :: _ -> Ptree.choose_leaf hd, hd
                    | _ -> failwith "No trees in memory"
                end
        in
        let res =
            Ptree.consensus
                PtreeSearch.default_collapse_function
                (fun code -> Data.code_taxon code data) majority
                (Sexpr.to_list trees) rooting_leaf
        in
        let fo = Status.Output (filename, false, []) in
        if not graphic then begin
            Status.user_message fo "@[<v>";
            Status.user_message fo
                ("@[" ^ majority_text ^ "@ Majority@ Consensus Tree@]@,@[");
            Status.user_message fo (AsciiTree.for_formatter false true false res);
            Status.user_message fo "@]@]\n%!";
        end else
            match filename with
            | Some filename ->
                let title = majority_text ^ " Majority Consensus Tree" in
                GraphicsPs.display title filename [|(0.0, res)|]
            | None -> 
                let r = AsciiTree.to_string ~sep:2 ~bd:2 true res in
                Status.user_message fo 
                    ("@[@[<v>@[" ^ majority_text ^ "@ Majority@ Consensus Tree@]@,@[");
                Status.user_message (Status.Output (filename,false, [])) r;
                Status.user_message (Status.Output (filename, false, [])) "@]@]@]%!";
end

module Make
    (NodeH : NodeSig.S with type other_n = Node.Standard.n) 
    (EdgeH : Edge.EdgeSig with type n = NodeH.n) 
    (TreeOpsH : Ptree.Tree_Operations with type a = NodeH.n with type b = EdgeH.e)
     =
struct

    module NodeS = Node.Standard
    module EdgeS = Edge.SelfEdge
    module TreeOpsS = Chartree.TreeOps

    type a = NodeH.n
    type b = EdgeH.e

    module SH = MakeNormal (NodeS) (EdgeS) (TreeOpsS)
    module DH = MakeNormal (NodeH) (EdgeH) (TreeOpsH)

    module TOS = TreeOpsS 
    module TOH = TreeOpsH 

    let report_trees = DH.report_trees
    let process_trees = DH.process_trees
    let forest_break_search_tree = DH.forest_break_search_tree
    let diagnose = DH.diagnose

    let collect_nodes data trees =
        let tree = Sexpr.first trees in
        let aux_collect key node taxaacc = match node with
            | Tree.Single _ | Tree.Leaf _ ->
                (Ptree.get_node_data key tree) :: taxaacc
            | _ ->
                taxaacc
        in
        let nodes =
            All_sets.IntegerMap.fold aux_collect tree.Ptree.tree.Tree.u_topo []
        in
        nodes, List.map NodeH.to_other nodes

    let replace_contents downpass uppass get_code nodes ptree =
        let nt = { (Ptree.empty ptree.Ptree.data) with Ptree.tree = ptree.Ptree.tree } in
        uppass (downpass 
        (List.fold_left (fun nt node ->
            Ptree.add_node_data (get_code node) node nt) 
        nt nodes))

    let from_s_to_h = replace_contents TOH.downpass TOH.uppass NodeH.taxon_code 
    let from_h_to_s = replace_contents TOS.downpass TOS.uppass NodeS.taxon_code

    let find_local_optimum ?base_sampler ?queue data b trees d e =
        if 0 = Sexpr.length trees then trees
        else
            let sampler =
                match base_sampler with
                | None -> new Sampler.do_nothing
                | Some x -> x 
            in
        match  Data.has_static_likelihood data || Data.has_dynamic data, queue with
            | true, None -> 
                DH.find_local_optimum ~base_sampler:sampler data b trees d e
            | true, Some queue -> 
                DH.find_local_optimum ~base_sampler:sampler ~queue data b trees d e
            | false, queue ->
                let nodeh, nodes = collect_nodes data trees in
                let trees = Sexpr.map (from_h_to_s nodes) trees in
                let trees = match queue with
                    | None       -> SH.find_local_optimum data b trees d e
                    | Some queue -> SH.find_local_optimum ~queue data b trees d e
                in
                Sexpr.map (from_s_to_h nodeh) trees

    let forest_search data b c d trees =
        if 0 = Sexpr.length trees then trees
        else
            if Data.has_dynamic data then
                DH.forest_search data b c d trees 
            else
                let nodeh, nodes = collect_nodes data trees in
                let trees = Sexpr.map (from_h_to_s nodes) trees in
                let trees = SH.forest_search data b c d trees in
                Sexpr.map (from_s_to_h nodeh) trees

    let fusing data a trees b =
        if Data.has_dynamic data then
            DH.fusing data a trees b
        else
            let nodeh, nodes = collect_nodes data trees in
            let trees = Sexpr.map (from_h_to_s nodes) trees in
            let trees = SH.fusing data a trees b in
            Sexpr.map (from_s_to_h nodeh) trees


    let output_consensus = DH.output_consensus
end
