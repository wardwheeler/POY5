(** This is potentially garbage, but we leave it because we might need some
* of the effort placed here somewhere else *)
(* A phylogenetic analysis machine written for the S_K computer 
* This machine uses the most simply defined functions, so we will start by
* defining some basic functionality *)
let u_Tl = SK (S K)
let u_Hd = SK K

exception Unsupported

module type List = sig
    type ocaml_repr
    type ocaml_list
    val empty_list : S_K.primitives
    val is_not_empty : S_K.primitives -> S_K.primitives
    val ml_zero_signal : S_K.primitives -> bool
    val head : S_K.primitives -> S_K.primitives
    val tail : S_K.primitives -> S_K.primitives
    val prepend : S_K.primitives -> S_K.primitives -> S_K.primitives
    val alphabet : (S_K.primitives * ocaml_repr) list
    val to_ocaml : S_K.primitives -> ocaml_repr
    val of_ocaml : ocaml_repr -> S_K.primitives
    val to_list : S_K.primitives -> ocaml_list
    val of_list : ocaml_list -> S_K.primitives
    val complement : S_K.primitives -> S_K.primitives
end

module UTree = Tree 

module type Tree = sig
    type ocaml_tree
    val leaf : S_K.primitives -> S_K.primitives
    val is_leaf : S_K.primitives -> S_K.primitives
    val ml_leaf_signal : S_K.primitives -> bool
    val contents : S_K.primitives
    val left : S_K.primitives
    val right : S_K.primitives
    val join : S_K.primitives -> S_K.primitives -> S_K.primitives -> S_K.primitives
    val to_tree : S_K.primitives -> ocaml_tree
    val of_tree : ocaml_tree -> S_K.primitives
end

module K_S : List with type ocaml_repr = [ `K | `SK] 
with type ocaml_list = [`K | `SK] list = struct
        type ocaml_repr = [ `K | `SK ]
        type ocaml_list = ocaml_repr list
        let empty_list = SK (Pair (K S) K)
        let is_not_empty x = SK ([x] [u_Hd] K K)
        let ml_zero_signal x = (SK (K S)) = S_K.eval (SK ([x] [u_Hd]))
        let head x = SK ([x] [u_Hd])
        let tail x = SK ([x] [u_Tl])
        let prepend a b = SK (Pair [a] [b])
        let alphabet = [`K, `K; (SK (S K)), `SK]
        let inv_alph = List.map (fun (a, b) -> (b, a)) alphabet
        let to_ocaml a = 
            let a = S_K.eval a in
            List.assoc a alphabet
        let of_ocaml a = List.assoc a inv_alph
        let to_list lst = 
            let rec to_list lst =
                if not (ml_zero_signal lst) then 
                    let next = to_ocaml (S_K.eval (head lst)) in
                    next :: (to_list (S_K.eval (tail lst)))
                else []
            in
            to_list (S_K.eval lst) 
        let rec of_list lst = 
            List.fold_right (fun x acc ->
                prepend (of_ocaml x) acc) lst empty_list
        let complement x = SK ([x] (S K) K)
end

type 'a btree = Node of ('a * 'a btree * 'a btree) | Leaf of 'a

module Tree : Tree with 
    type ocaml_tree = S_K.primitives btree = struct

    type ocaml_tree = S_K.primitives btree

    let leaf x = SK (Pair K [x])

    let is_leaf x = SK ([x] [u_Hd])

    let ml_leaf_signal x = (SK K) = S_K.eval (SK ([x] [u_Hd]))

    let contents = 
        S_K.create 
        (SK ((tree [u_Hd]) (tree [u_Tl]) (tree [u_Tl][u_Hd])))
        (LS tree)

    let left =
        S_K.create
        (SK (tree [u_Tl] [u_Tl] [u_Hd]))
        (LS tree)

    let right =
        S_K.create
        (SK (tree [u_Tl] [u_Tl] [u_Tl]))
        (LS tree)

    let join a b c =
        SK (Pair (S K) (Pair [c] (Pair [a] [b])))

    let rec to_tree x =
        let contents = (S_K.eval (SK ([contents] [x]))) in
        if ml_leaf_signal x then Leaf contents
        else 
            let left = S_K.eval (SK ([left] [x]))
            and right = S_K.eval (SK ([right] [x])) in
            Node (contents, to_tree left, to_tree right)

    let rec of_tree tree =
        match tree with
        | Leaf x -> leaf x
        | Node (x, a, b) -> join (of_tree a) (of_tree b) x
end

module type Integer = sig
    val zero : S_K.primitives
    val not_zero : S_K.primitives -> S_K.primitives
    val ml_zero_signal : S_K.primitives -> bool
    val predecessor : S_K.primitives -> S_K.primitives
    val successor : S_K.primitives -> S_K.primitives
    val to_int : S_K.primitives -> int
    val of_int : int -> S_K.primitives
end

module ChurchIntegers : Integer = struct
    (* A representation of integers using Church's original list
    * representation with as many K as there can be *)
    let zero = S_K.eval (SK (Pair (K S) K))
    let not_zero x = S_K.eval (SK ([x] [u_Hd] K K))
    let ml_zero_signal x = 
       (SK (S K)) = S_K.eval (SK ([x] [u_Hd] K K))
    let predecessor x = SK ([x] [u_Tl])
    let successor x = SK (Pair K [x])
    let to_int a = 
        let rec aux_to_int acc a =
            if ml_zero_signal a then acc
            else aux_to_int (acc + 1) (predecessor a)
        in
        aux_to_int 0 a
    let of_int a = 
        let rec aux_of_int acc a =
            if a = 0 then acc
            else aux_of_int (successor acc) (a - 1)
        in
        S_K.eval (aux_of_int zero a)
end

module Dna : List with type ocaml_repr = string with type ocaml_list =
    string list = struct
    (* A representation of DNA sequences *)
    type ocaml_repr = string
    type ocaml_list = string list
    let empty_list = S_K.eval (SK (Pair (Pair (K S)  K) K))
    let is_not_empty x = (SK ([x] [u_Hd] [u_Hd] K K))
    let ml_zero_signal x = 
       (SK (K S)) = S_K.eval (SK ([x] [u_Hd] [u_Hd]))
    let head x = SK ([x] [u_Hd])
    let tail x = SK ([x] [u_Tl])
    let prepend x y = SK (Pair [x] [y])
    let alphabet = 
        List.map (fun (a, b) -> S_K.eval a, b)
        [(SK (Pair K K), "A"); (SK (Pair K (S K)), "C"); 
        (SK (Pair (S K) K), "G"); (SK (Pair (S K) (S K)), "T")]
    let inv_alph = List.map (fun (a, b) -> (b, a)) alphabet
    let to_ocaml a = 
        match S_K.eval (SK (Hd [a])), S_K.eval (SK (Tl [a])) with
        | `K, `K -> "A"
        | `K, `Node [`S; `K] -> "C"
        | `Node [`S; `K], `K -> "G"
        | `Node [`S; `K], `Node [`S; `K] -> "T"
        | _ -> raise Not_found

    let of_ocaml a = List.assoc a inv_alph
    let complement x =
        let negate n = S_K.eval (SK ([x] [n] (S K) K)) in
        let a = negate u_Hd
        and b = negate u_Tl in
        S_K.eval (SK (Pair [a] [b]))
    let to_list lst = 
        let rec to_list lst =
            if not (ml_zero_signal (S_K.eval lst)) then 
                let next = to_ocaml (S_K.eval (head lst)) in
                next :: (to_list (tail lst))
            else []
        in
        to_list (S_K.eval lst) 
    let rec of_list lst = 
        List.fold_right (fun x acc ->
            prepend (of_ocaml x) acc) lst empty_list
end

module ComposableBase = struct
    let decode_function =
        let tmp_df =
            S_K.create 
            (SK ([Tree.is_leaf (SK encoder_in_use)]
                ([Tree.contents] encoder_in_use acc starter
                R original_f_encoder lst)
                (R acc starter original_f_encoder ((lst [u_Hd]) ([Tree.left]
                encoder_in_use) ([Tree.right] encoder_in_use)) (lst
                [u_Tl]))))
            (LS R acc starter original_f_encoder encoder_in_use lst)
        in
        S_K.create (SK (Fixedpoint [tmp_df])) []

    (* starter R decode_function original_f_encoder acc lst 
    * decode_function R acc starter original_f_encoder encoder_in_use lst
    * insert R acc starter decode_function original_f_encoder lst
    * delete R acc starter decode_function original_f_encoder lst
    * substitute R acc starter decode_function original_f_encoder lst *)
    let starter =
        let tmp_starter =
            S_K.create 
            (SK (((lst [u_Hd]) K K) 
                (decode_function acc R original_f_encoder original_f_encoder
                lst)
                acc))
            (LS R decode_function original_f_encoder acc lst)
        in
        S_K.create (SK (Fixedpoint [tmp_starter] [decode_function])) []


end

module type IntegerRepresentation = sig
    type extras
    (* A module type to convert from a given type to ChurchIntegers which
    * are easier to deal with *)
    val of_int : extras -> int -> S_K.primitives
    val to_int : extras -> S_K.primitives -> int
    val to_church : extras -> S_K.primitives
end

module ComposableAtomicSE = struct
    (* insert R pos base acc starter decode_function original_f_encoder lst
    * *)
    let aux_insert =
        let tmp_i =
            S_K.create 
            (SK ([ChurchIntegers.not_zero (SK pos)]
                [Dna.prepend (Dna.head (SK acc)) 
                    (SK (R ([ChurchIntegers.predecessor (SK pos) ]) base 
                    [Dna.tail (SK acc)] starter
                    decode_function original_f_encoder lst))]
                ([Dna.prepend (SK base) (SK (starter
                decode_function original_f_encoder acc lst))])))
            (LS R pos base acc starter decode_function original_f_encoder
            lst)
        in
        S_K.create (SK (Fixedpoint [tmp_i])) []

    let aux_delete = 
        let tmp_d =
            S_K.create
            (SK ([ChurchIntegers.not_zero (SK pos)]
                [Dna.prepend (SK [Dna.head (SK acc)]) (SK (R
                ([ChurchIntegers.predecessor (SK pos)]) [Dna.tail (SK acc)] starter
                decode_function original_f_encoder lst))]
                (starter decode_function
                original_f_encoder [Dna.tail (SK acc)] lst)))
            (LS R pos acc starter decode_function original_f_encoder
            lst)
        in
        S_K.create (SK (Fixedpoint [tmp_d])) []

    let aux_substitute =
        let tmp_s =
            S_K.create 
            (SK ([ChurchIntegers.not_zero (SK pos)]
                [Dna.prepend (Dna.head (SK acc)) (SK (R
                ([ChurchIntegers.predecessor (SK pos) ]) base [Dna.tail (SK
                acc)] starter
                decode_function original_f_encoder lst))]
                ([Dna.prepend (SK base) (SK (starter
                decode_function original_f_encoder [Dna.tail (SK acc)] lst))])))
            (LS R pos base acc starter decode_function original_f_encoder
            lst)
        in
        S_K.create (SK (Fixedpoint [tmp_s])) []

    let insert to_church = 
        S_K.create 
        (SK ([aux_insert] ([to_church] (lst [u_Hd])) (lst [u_Tl] [u_Hd]) acc starter
        decode_function original_f_encoder (lst [u_Tl] [u_Tl])))
        (LS acc starter decode_function original_f_encoder lst)

    let delete to_church =
        S_K.create 
        (SK ([aux_delete] ([to_church] (lst [u_Hd])) acc starter
        decode_function original_f_encoder (lst [u_Tl])))
        (LS acc starter decode_function original_f_encoder lst)

    let substitute to_church = 
        S_K.create 
        (SK ([aux_substitute] ([to_church] (lst [u_Hd])) (lst [u_Tl] [u_Hd]) acc starter
        decode_function original_f_encoder (lst [u_Tl] [u_Tl])))
        (LS acc starter decode_function original_f_encoder lst)

    let editions of_int a b =
        let len = String.length a in
        if len <> String.length b then failwith "Sequences not aligned"
        else
            let rec comparator pos delta =
                if pos = len then (SK (Pair (K S) K))
                else
                    let np = pos + 1 in
                    if a.[pos] = b.[pos] then comparator np (delta + 1) 
                    else if b.[pos] = '-' then 
                        (SK (Pair (S K) (Pair (S K) (Pair [of_int delta]
                        [comparator np 0]))))
                    else if a.[pos] = '-' then 
                        (SK (Pair (S K) (Pair K (Pair [of_int delta]
                        (Pair [Dna.of_ocaml (String.make 1 b.[pos])] 
                        [comparator np 0])))))
                    else 
                        (SK (Pair K (Pair [of_int delta]
                        (Pair [Dna.of_ocaml (String.make 1 b.[pos])] 
                        [comparator np 0]))))
            in
            comparator 0 0

end

module Chromosome : List with type ocaml_repr = Dna.ocaml_list with type
ocaml_list = Dna.ocaml_list list = struct

    type ocaml_repr = string list
    type ocaml_list = string list list 

    let empty_list = SK (Pair [Dna.empty_list] K)

    let is_not_empty x = Dna.is_not_empty (SK ([x] [u_Hd]))

    let ml_zero_signal x = Dna.ml_zero_signal (SK ([x] [u_Hd]))

    let head x = SK ([x] [u_Hd])
    let tail x = SK ([x] [u_Tl])
    let prepend x y = SK (Pair [x] [y])
    let alphabet = []
    let to_ocaml item = Dna.to_list item
    let of_ocaml lst = Dna.of_list lst
    let rec to_list x = 
        if ml_zero_signal x then []
        else (to_ocaml (head x)) :: (to_list (tail x))
    let of_list x =
        List.fold_right (fun x acc ->
            SK (Pair [of_ocaml x] [acc])) x empty_list
    let complement _ = raise Unsupported
end

module Debugger (R : List) = struct
    let rec string_list (lst : S_K.primitives) =
        if R.ml_zero_signal lst then 
            (R.to_ocaml (S_K.eval (R.head lst))) :: 
                string_list (S_K.eval (R.tail lst))
        else []
end

module type SE = sig 
    (* A sequence edition module that provides the functions required to
    * edit sequences of some predefined alphabet using the integer and
    * sequence representation of the programmer choice *)

    (** {2 Sequence Edition Functions}
     *
     * A sequence edition function is a machine in the SK language that
     * supports operations in sequences of a given alphabet. Different 
     * restrictions for representation and degree of functionality can 
     * be specified for each module implementing [SE].  *)

    (** [insert] inserts subsequences in another sequence. *)
    val insert : S_K.primitives

    (** [delete] deletes subsequences in another sequence. *)
    val delete : S_K.primitives

    (** [substitute] substitutes subseuqneces in another sequence. *)
    val substitute : S_K.primitives

    (** {2 Ocaml Interface}
     *
     * The following types and functions simplify the generation of SK
     * machines for particular [insert], [delete], and [substitute]
     * operations using the OCaml types directly. *)

    type insert_generator 
    type delete_generator 
    type substitute_generator
    val insert_generator : insert_generator
    val delete_generator : delete_generator
    val substitute_generator : substitute_generator

end

module AtomicSE (I : Integer) (S : List) : SE 
    with type insert_generator = int -> S.ocaml_repr -> S_K.primitives
    with type delete_generator = int -> S_K.primitives
    with type substitute_generator = int -> S.ocaml_repr -> S_K.primitives 
    = struct
    (* Atomic operations on sequences. The integer representation is that
    * provided by I, and the sequence representation is that provided by S. 
    * In AtomicSE, all the operations are atomic, in other words,
    * insertions, deletions, and substitutions occur in a single alphabet
    * element at a time basis. In other words, each occurs independently
    * along the sequence, one base at a time. *)

    (* A simplified function to generate all the atomic operations with
    * standard recursion until a zero condition is true *)
    let until_zero_recursions lst pos if_zero if_not_zero =
        let simple_recursion =
            S_K.create (SK 
                ([I.not_zero (SK pos)]
                    [if_not_zero] 
                    [if_zero])) 
            lst
        in
        S_K.expand (SK (Fixedpoint [simple_recursion]))

    (** [insert p b s] inserts the element [b] belonging to
    * the alphabet of [S] in the position [p] as represented by the module
    * [I] in the sequence [s] as represented by the module [S]. The
    * positions is counted from the 0 index from left to right.*)
    let insert = 
        until_zero_recursions
        (LS R pos base seq)
        (SK pos)
        (S.prepend (SK base) (SK seq))
        (S.prepend (S.head (SK seq))
        (SK (R [I.predecessor (SK pos)] base [S.tail (SK seq)])))

    (** [delete p s] deletes the element located in position
    * [p] as represented by [I] of the sequence [s] as represented by [S].
    * The position is counted from the 0 index from left to right. *)
    let delete = 
        until_zero_recursions
        (LS R pos seq)
        (SK pos)
        (S.tail (SK seq))
        (S.prepend 
            (S.head (SK seq)) 
            (SK (R [I.predecessor (SK pos)] [S.tail (SK seq)])))

    (** [substitute p b s] substitutes the element located
    * in position [p] as represented by [I] with the element [b] from the 
    * alphabet supported by [S] in the sequence [s] as represented by [S].
    * The position is counted from the 0 index from left to right. *)
    let substitute =
        until_zero_recursions
        (LS R pos base seq)
        (SK pos)
        (S.prepend (SK base) (S.tail (SK seq)))
        (S.prepend (S.head (SK seq))
            (SK (R [I.predecessor (SK pos)] base [S.tail (SK seq)])))

    (** [insert_generator p b] takes the position [p] and element [b] to be 
    * inserted, and produces a machine that only requires the sequence on 
    * which to be inserted. *)
    type insert_generator = int -> S.ocaml_repr -> S_K.primitives

    (** [delete_generator p] takes the position [p] and produces a machine
    * that only requires the sequence on which that position should be
    * deleted. *)
    type delete_generator = int -> S_K.primitives

    (** [substitute_generator p b] takes the position [p] and element [b]
     * and generates a machine that only requires the sequence on which the
     * substitution will be performed. *)
    type substitute_generator = int -> S.ocaml_repr -> S_K.primitives

    let insert_generator pos base = 
        SK ([insert] [I.of_int pos] [S.of_ocaml base])

    let delete_generator pos =
        SK ([delete] [I.of_int pos])

    let substitute_generator pos base =
        SK ([substitute] [I.of_int pos] [S.of_ocaml base])
end

module AffineSE (I : Integer) (S : List) : SE 
    with type insert_generator = int -> S_K.primitives
    with type delete_generator = int -> int ->  S_K.primitives
    with type substitute_generator = int -> S_K.primitives
    = struct

    (** [insert p pref s] inserts the sequence [pref] as represented in [S]
     * in the position [p] as represented in [I] in the sequence [s] as
     * represented in [S]. *)
    let insert = 
        (* Instead of passing a single base, we will pass a
        complete sequence to this function *)
        let tmp = 
            S_K.create 
            (SK ([I.not_zero (SK pos)]
                (* If we are not in position 0 we continue *)
                [S.prepend (S.head (SK seq)) 
                    (SK (R [I.predecessor (SK pos)] prefix 
                    [S.tail (SK seq)]))]
                (* We have reached the position, we better merge now *)
                ([S.is_not_empty (SK prefix)]
                (* If we have some base left in the sequence that we will 
                * insert *)
                    [S.prepend (S.head (SK prefix)) 
                        (SK (R pos [S.tail (SK prefix)] seq))]
                        (* Otherwise we have finished inserting *)
                        seq)))
            (LS R pos prefix seq)
        in
        S_K.expand (SK (Fixedpoint [tmp]))

    (** [delete p len s] deletes a section of length [len] starting in
    * position [p] as represented in [I] in the sequence [s] as
     * represented in [S]. *)
    let delete =
        let tmp =
            S_K.create
            (SK ([I.not_zero (SK pos)] 
                (* If we haven't reached the deletion pos *)
                [S.prepend (S.head (SK seq))
                    (SK (R [I.predecessor (SK pos)] len 
                        [S.tail (SK seq)]))]
                (* If we have reached the deletion pos *)
                ([I.not_zero (SK len)]
                    (* We still have something more to del *)
                    (R pos [I.predecessor (SK len)] [S.tail (SK seq)])
                    (* We are done with the deletion *)
                    seq)))
            (LS R pos len seq)
        in
        S_K.expand (SK (Fixedpoint [tmp]))

    (** [substitute p pref s] substitutes the sequence [pref] as represented in [S]
     * in the position [p] as represented in [I] in the sequence [s] as
     * represented in [S]. *)
    let substitute =
        let tmp =
            S_K.create
            (SK ([I.not_zero (SK pos)] 
            (* If we haven't reached the deletion position *)
                [S.prepend (S.head (SK seq)) 
                (SK (R [I.predecessor (SK pos)] repl [S.tail (SK seq)]))]
                (* We have reached the deletion position *)
                ([S.is_not_empty (SK repl)] 
                    (* Still some more to substitute *)
                    [S.prepend (S.head (SK repl))
                    (SK (R pos [S.tail (SK repl)] [S.tail (SK seq)]))]
                    (* Nothing else to substitute *)
                    seq)))
            (LS R pos repl seq)
        in
        S_K.expand (SK (Fixedpoint [tmp]))

    (** [insert_generator pos] generates an insertion machine in position
    * [pos] requiring only as input the sequence to insert and the sequence
    * where the insertion is to be performed *)
    type insert_generator = int -> S_K.primitives 

    (** [delete_generator pos len] generates a deletion machine in position
    * [pos] with length [len] and requires only as input the sequence where
    * the deletion is to be performed *)
    type delete_generator = int -> int -> S_K.primitives

    (** [substitute_generator pos] does the same as [insert_generator] but
    * for a substitution event. *)
    type substitute_generator = int -> S_K.primitives 

    let insert_generator pos = 
        SK ([insert] [I.of_int pos])

    let delete_generator pos len =
        SK ([delete] [I.of_int pos] [I.of_int len])

    let substitute_generator pos =
        SK ([substitute] [I.of_int pos])
end


module LogInt : IntegerRepresentation with type extras = unit = struct
    type extras = unit

    let of_int () int =
        let rec encode_in_log int acc =
            if int = 0 then acc
            else 
                encode_in_log (int lsr 1)
                (SK (Pair [if 1 = (1 land int) then (SK K) else (SK (S K))]
                [acc]))
        in
        if int < 0 then failwith "Illegal argument"
        else encode_in_log int (SK EmptyList)

    let to_int () x =
        let lst = K_S.to_list x in
        List.fold_left (fun acc item ->
            (2 * acc) +
            (match item with
            | `K -> 1 
            | `SK -> 0)) 0 lst

    let to_church () = SK DecodeInt 

end

module EncodedInteger : IntegerRepresentation with 
type extras = int option UTree.Parse.t = struct
    type extras = int option UTree.Parse.t 

    let rec encoder tree =
        match tree with
        | UTree.Parse.Leafp (Some x) -> Tree.leaf (LogInt.of_int () x)
        | UTree.Parse.Nodep ([l;r ], None) ->
                Tree.join (encoder l) (encoder r) (SK K)
        | _ -> failwith "Illegal tree"

    let decoder =
        let tmp =
            S_K.create 
            (SK ([Tree.is_leaf (SK encoder)] 
            ([Tree.contents] encoder)
            (R ([K_S.head (SK lst)] ([Tree.left] encoder) ([Tree.right]
            encoder)) [K_S.tail (SK lst)])))
            (LS R encoder lst)
        in
        S_K.create (SK (Fixedpoint [tmp])) []



    let of_int tree int =
        let rec aux_int tree =
            match tree with
            | UTree.Parse.Leafp (Some x) ->
                    if x = int then Some (SK K)
                    else None
            | UTree.Parse.Nodep ([l; r], None) ->
                    (match aux_int l with
                    | None ->
                            (match aux_int r with
                            | None -> None
                            | Some x -> Some (SK (Pair (S K) [x])))
                    | Some x -> Some (SK (Pair K [x])))
            | _ -> assert false
        in
        match aux_int tree with
        | None -> prerr_int int; prerr_newline (); assert false
        | Some x -> x

    let rec to_int tree int =
        match tree with
        | UTree.Parse.Leafp (Some x) -> x
        | UTree.Parse.Nodep ([l; r], None) ->
                (match S_K.eval (SK (Hd [int])) with
                | `K -> to_int l (SK (Tl [int])) 
                | `Node [`S; `K] -> to_int r (SK (Tl [int]))
                | _ -> assert false)
        | _ -> assert false

    let to_church tree =
        let enc = encoder tree in
        let log = LogInt.to_church () in
        S_K.create (SK ([log] ([decoder] [enc] int))) (LS int)

end


module FixedMax : IntegerRepresentation with type extras = int = struct

    type extras = int 

    let of_int max int =
        let rec encode_in_log max int acc =
            if max = 0 then acc
            else 
                encode_in_log (max lsr 1) (int lsr 1) 
                (SK (Pair [if 1 = (1 land int) then (SK K) else (SK (S K))]
        [acc]))
        in
        if int < 0 || max < 0 || max < int then failwith "Illegal argument"
        else encode_in_log max int (SK K)

    let to_church max =
        let rec aux_len max acc =
            if max = 0 then acc 
            else aux_len (max lsr 1) (acc + 1) 
        in
        if max < 0 then failwith "Illegal argument" 
        else
            let counter = ChurchIntegers.of_int (aux_len max 0) in
            let tmp_rec = 
                S_K.create
                (SK ([ChurchIntegers.not_zero (SK cnt)]
                    (R [ChurchIntegers.predecessor (SK cnt)] 
                    ((int [u_Hd]) 
                        (Add [ChurchIntegers.of_int 1] (Multiply
                        [ChurchIntegers.of_int 2] acc)) 
                        (Multiply [ChurchIntegers.of_int 2] acc))
                        (int [u_Tl]))
                    acc))
                (LS R cnt acc int)
            in
            S_K.create 
            (SK (Fixedpoint [tmp_rec] [counter] [ChurchIntegers.zero])) 
            []

    let to_int max int = 
        ChurchIntegers.to_int 
        (S_K.eval (SK ([to_church max] [int])))

end

module FixedRange : IntegerRepresentation with type extras = (int * int) =
    struct
        type min = int
        type max = int
        type extras = (min * max)

        let of_int (min, max) int =
            if min > max || int < min || int > max then 
                failwith "Illegal argument"
            else
                FixedMax.of_int (max - min) int

        let to_int (min, max) int =
            min + (FixedMax.to_int (max - min) int)

        let to_church (min, max) =
            S_K.create
            (SK (Add [ChurchIntegers.of_int min] ([FixedMax.to_church (max -
            min)] pos))) (LS pos)
end

let convert_to_log_position x = 
    S_K.expand (S_K.create (SK ([x] (DecodeInt pos))) (LS pos))

(* We are almost there, let's make a function that encodes an integer in
* it's logarithmic binary representation *)
let encode_in_log int =
    let rec encode_in_log int acc =
        if int = 0 then acc
        else 
            encode_in_log (int lsr 1)
            (SK (Pair [if 1 = (1 land int) then (SK K) else (SK (S K))]
            [acc]))
    in
    if int < 0 then failwith "Illegal argument"
    else encode_in_log int (SK EmptyList)

module AtomicSE_LogInts (S : SE) : SE
    with type insert_generator = int -> S_K.primitives
    with type delete_generator = int -> S_K.primitives
    with type substitute_generator = int -> S_K.primitives 
    = struct

    let generic f = S_K.create (SK ([f] ([LogInt.to_church ()] pos))) (LS pos)
    let insert = generic S.insert
    let delete = generic S.delete
    let substitute = generic S.substitute

    type insert_generator = int -> S_K.primitives 
    type delete_generator = int -> S_K.primitives
    type substitute_generator = int -> S_K.primitives 

    let insert_generator pos = 
        SK ([insert] [LogInt.of_int () pos])

    let delete_generator pos =
        SK ([delete] [LogInt.of_int () pos])

    let substitute_generator pos =
        SK ([substitute] [LogInt.of_int () pos])
end

module ComposableSE (L : List) (I : IntegerRepresentation) = struct
    let starter =
        let tmp =
            S_K.create
            (SK (((lst [u_Hd]) K K) (decoder acc R lst) (acc)))
            (LS acc lst decoder)
        in
        S_K.create (SK (Fixedpoint [tmp]))

    let decoder =
        let tmp =
            S_K.create
            (SK ([Tree.is_leaf (SK tree_in_use)] 
                (([Tree.contents] tree_in_use) 
                (R starter original_tree original_tree)
                    starter lst)
                (R starter original_tree 
                    ((lst [u_Hd]) ([Tree.left] tree_in_use) 
                        ([Tree.right] tree_in_use)) (lst [u_Tl]) acc)))
            (LS starter original_tree tree_in_use lst acc)
        in
        S_K.create (SK (Fixedpoint [tmp])) []
end

module AffineSE_LogInts (S : SE) : SE 
    with type insert_generator = int -> S_K.primitives
    with type delete_generator = int -> int -> S_K.primitives
    with type substitute_generator = int -> S_K.primitives 
    = struct
    let generic f = S_K.create (SK ([f] ([LogInt.to_church ()] pos))) (LS pos)
    let insert = generic S.insert
    let delete = 
        S_K.create (SK ([S.delete] ([LogInt.to_church ()] pos)
        ([LogInt.to_church ()] len)))
        (LS pos len)
    let substitute = generic S.substitute

    type insert_generator = int -> S_K.primitives 
    type delete_generator = int -> int -> S_K.primitives
    type substitute_generator = int -> S_K.primitives 

    let insert_generator pos = 
        SK ([insert] [LogInt.of_int () pos])

    let delete_generator pos len =
        SK ([delete] [LogInt.of_int () pos] 
        [encode_in_log len])

    let substitute_generator pos =
        SK ([substitute] [LogInt.of_int () pos])
end

module type HO = sig
    include SE
    val translocate : S_K.primitives
    val invert : S_K.primitives
    val duplicate : S_K.primitives
    val tandem : S_K.primitives
end

module type GO = sig
    include HO
    val chr_translocation : S_K.primitives
    val chr_crossover : S_K.primitives
end

module HighOrder (I : Integer) (S : List) : HO = 
    struct
    module Aff = AffineSE (I) (S)

    include Aff 

    let extract_subsequence =
        let tmp =
            S_K.create (SK ([I.not_zero (SK start)]
                (R [I.predecessor (SK start)] len [S.tail (SK seq)])
                ([I.not_zero (SK len)]
                    ([S.prepend (S.head (SK seq)) 
                        (SK (R [I.zero] [I.predecessor (SK len)] 
                        [S.tail (SK seq)]))])
                    [S.empty_list])))
            (LS R start len seq)
        in
        S_K.create (SK (Fixedpoint [tmp])) []

    let invert_seq = 
        let tmp =
            S_K.create 
            (SK ([S.is_not_empty (SK seq)]
                (R ([S.prepend (S.complement (S.head (SK seq))) (SK acc)])
                ([S.tail (SK seq)]))
                acc))
            (LS R acc seq)
        in
        S_K.create (SK (Fixedpoint [tmp])) []

    let translocate =
        S_K.create
        (SK ([Aff.insert] ins_pos ([extract_subsequence] tran_pos len seq) 
        ([Aff.delete] tran_pos len seq)))
        (LS ins_pos tran_pos len seq)

    let duplicate = 
        S_K.create
        (SK ([Aff.insert] ins_pos ([extract_subsequence] tran_pos len seq)
        seq))
        (LS ins_pos tran_pos len seq)

    let invert =
        S_K.create 
        (SK ([Aff.insert] pos ([invert_seq] [S.empty_list] ([extract_subsequence]
        pos len seq)) ([Aff.delete] pos len seq)))
        (LS pos len seq)

    let tandem =
        let tmp =
            S_K.create
            (SK ([I.not_zero (SK rep)]
                ([duplicate] pos pos len (R [I.predecessor (SK rep)] pos len seq ))
                (seq)))
            (LS R rep pos len seq)
        in
        S_K.create (SK (Fixedpoint [tmp])) []
end

(*
(* A encoded is made of pairs in the following way:
    * (Pair K (Pair encoded encoded))
    * (Pair (K S) Result)
    * Where left (K) or right (S K) of the right element represent the
    * actual path to be followed from the list. *)
let decoder simplified =
    let next_encoder = (SK ((encoder [u_Tl]) (lst [u_Hd]))) in
    let decoder_recursion =
        S_K.create 
        (SK ([next_encoder] [u_Hd] K K (R (lst [u_Tl]) [next_encoder]) 
        [if simplified then
            (SK ([next_encoder] [u_Tl]))
        else
            (SK (Pair ([next_encoder] [u_Tl]) (lst [u_Tl])))]))
        (LS R lst encoder)
    in
    S_K.expand (SK (Fixedpoint [decoder_recursion]))

let rec make_encoder tree leafs =
    match tree with
    | `Node [a; b] -> 
            (SK (Pair K (Pair [make_encoder a leafs] [make_encoder b
            leafs])))
    | `Label x -> 
            (SK (Pair (K S) [try (List.assoc x leafs) with Not_found ->
                tree]))
    | `S -> (SK (Pair (K S) S))
    | `K -> (SK (Pair (K S) K))
    | `Node _ -> failwith "Illegal encoder: each node must have two leafs"

(* An example of encoder and decoder usage *)
let encoder_example = make_encoder (SK (substitute (delete insert))) []

let result_example = 
    let decoder = S_K.expand (decoder false) in
    S_K.reduce (S_K.expand (SK (([decoder] [(SKLS (S K) (S K))] [encoder_example])
    [u_Hd])))

(* Each function is specified the number of items that need to be read. The
* accumulator for all the calculations is always the last item to be added.
* As the number of arguments is so small, we are better off specifying them
* in the simplest way, not using the logarithmic, but the standard notation.
* 
* So our representation consists of a list of items that are read one after
* the other and are fed to the encoder and the sequence representation.
* *)

(* The following concept:
    * fun f_apply decoder acc list =
        * fun apply acc list =
            * if list is empty then acc
            * else apply (acc (hd list)) (tl list) 
        * in
*         ((apply (decoder (hd list)) (tl list)) acc)
*  In order to use it, we need to have a tree (made of pairs) of the following 
*  form:
    *  (encoded_function, list_of_arguments)
    *  Where the list of arguments is
    *  (K, (Argument, list_of_arguments))
    *  ((K S), (K S)) if we have reach the end of the arguments.
*         *)
let f_apply =
    let apply =
        let tmp =
            S_K.create
            (SK ((lst [u_Hd] K K) (R (acc (lst [u_Tl] [u_Hd])) (lst [u_Tl]
            [u_Tl])) acc))
            (LS R acc lst)
        in
        S_K.create (SK (Fixedpoint [tmp])) []
    in
    S_K.create (SK (([apply] ([decoder false] (lst [u_Hd]) encoder  [u_Hd]) (lst [u_Tl])) acc)) 
    (LS acc encoder lst)

(* An example using it: 
let () = 
    let r =  
        S_K.eval (SK ([f_apply] [SKLS [adenine]] [make_encoder (SK (Delete
        (Insert Substitute))) ["Delete", delete; "Insert", insert; "Substitute",
        substitute]] [SKLS [SKLS K] K EmptyList])) in
    ()
*)

let swap = S_K.create (SK (a b)) (LS b a)

(* Now we can define the edition of sequences using a composition of
* editions. In other words, we don't need to specify the absolute position
* of a base for a deletion, but we can specify the relative position from
* the previous edition. This could produce a gain if the editions are dense
* enough. To do this, we will define another function similar to the
* [f_apply] that we just defined. *)

let apply_list_of_functions_on_accumulator =
    let recursion = 
        S_K.create
        (SK ((todo [u_Hd] K K)  (* We are not done yet *)
            ([decoder true] (todo [u_Tl] [u_Hd]) encoder R acc encoder 
            (todo [u_Tl] [u_Tl]))
            (acc)))
        (LS R acc encoder todo)
    in
    S_K.expand (SK (Fixedpoint [recursion]))

let insert_composable = 
    let insert_composable =
        until_zero_recursions
        (LS R Continue pos base seq encoder todo)
        (SK pos)
        (SK (Pair base (Continue seq encoder todo)))
        (SK (Pair (seq [u_Hd]) (R Continue (pos [u_Tl]) base (seq [u_Tl])
        encoder todo)))
    in
    let pos = SK (DecodeInt (todo [u_Hd]))
    and base = SK (todo [u_Tl] [u_Hd]) 
    and rest = SK (todo [u_Tl] [u_Tl]) in
    S_K.create
    (SK ([insert_composable] Continue [pos] [base] seq encoder [rest]))
    (LS Continue seq encoder todo)

let delete_composable =
    let delete_composable = 
        until_zero_recursions
        (LS R Continue pos seq encoder todo)
        (SK pos)
        (SK (Continue (seq [u_Tl]) encoder todo))
        (SK (Pair (seq [u_Hd]) (R Continue (pos [u_Tl]) (seq [u_Tl]) encoder
        todo)))
    in
    let pos = SK (DecodeInt (todo [u_Hd]))
    and rest = SK (todo [u_Tl]) in
    S_K.create
    (SK ([delete_composable] Continue [pos] seq encoder [rest])) 
    (LS Continue seq encoder todo)

let substitute_composable =
    let substitute_composable = 
        until_zero_recursions
        (LS R Continue pos base seq encoder todo)
        (SK pos)
        (SK (Pair base (Continue (seq [u_Tl]) encoder todo)))
        (SK (Pair (seq [u_Hd]) (R Continue (pos [u_Tl]) base (seq [u_Tl])
        encoder todo)))
    in
    let pos = SK (DecodeInt (todo [u_Hd]))
    and base = SK (todo [u_Tl] [u_Hd]) 
    and rest = SK (todo [u_Tl] [u_Tl]) in
    S_K.create
    (SK ([substitute_composable] Continue [pos] [base] seq encoder [rest]))
    (LS Continue seq encoder todo)

let is_not_empty_sequence x = SK ([x] [u_Hd] [u_Hd] K K)

let empty_sequence = SK (Pair EmptyList EmptyList)

(* A function to merge a pair of sequences. The only condition is that the
* empty sequence is represented by a pair of `Label "EmptySequence". *)
let merge_sequences =
    let merge_recursive =
        S_K.create
        (SK ([is_not_empty_sequence (SK prefix)]
        (* We have a base *)
        (Pair (prefix [u_Hd]) (R (prefix [u_Tl]) sufix))
        sufix))
        (LS R prefix sufix) 
    in
    S_K.create (SK (Fixedpoint [merge_recursive])) []

let inversion_without_complement = (* A standard inversion function *)
    let inversion_recursive =
        S_K.create
        (SK ([is_not_empty_sequence (SK original)]
        (* We still have to continue inverting *)
        (R (Pair (original [u_Hd]) result) (original [u_Tl]))
        original))
        (LS R result original)
    in
    S_K.create (SK (Fixedpoint [inversion_recursive])) []

let inversion_with_complement =
    let complement_base x = 
        SK (Pair (Not ([x] [u_Hd])) (Not ([x] [u_Tl])))
    in
    let inversion_recursive =
        S_K.create
        (SK ([is_not_empty_sequence (SK original)]
        (* We still have to continue inverting *)
        (R (Pair [complement_base (SK (original [u_Hd]))] result) 
        (original [u_Tl])) original))
        (LS R result original)
    in
    S_K.create (SK (Fixedpoint [inversion_recursive])) []

let extract_subsequence =
    let extract_recursive =
        S_K.create
        (SK ((pos [u_Hd] K K) (* We are not in the 0 position of the
        extraction *)
            (R (pos [u_Tl]) len (seq [u_Tl]))
            ((len [u_Hd] K K) (* We have more things to append *)
                (Pair (seq [u_Hd]) (R pos (len [u_Tl]) (seq [u_Tl])))
                [empty_sequence])))
        (LS R pos len seq)
    in
    S_K.create (SK (Fixedpoint [extract_recursive])) []

let duplicate = 
    S_K.create
    (SK ([affine_insert] pos ([extract_subsequence] beg len seq) seq))
    (LS pos beg len seq)

let translocate =
    S_K.create
    (SK ([affine_insert] pos ([extract_subsequence] beg len seq)
    ([affine_delete] pos len seq)))
    (LS pos beg len seq)

(* Now take a list of elements that can be passed to [lst] of f_apply and
* apply on each one of the [f_apply]. This way we can perform a row of edits
* in an accumulator that is passed around constantly. *)
let f_edit =
    let tmp = S_K.create
        (SK ((lst [u_Hd] K K) 
        (R encoder (lst [u_Tl] [u_Tl]) ([f_apply] acc encoder (lst [u_Tl]
        [u_Hd]))) acc)) 
        (LS R encoder lst acc)
    in
    S_K.create (SK (Fixedpoint [tmp])) []

(* We are almost there, let's make a function that encodes an integer in
* it's logarithmic binary representation *)
let encode_in_log int =
    let rec encode_in_log int acc =
        if int = 0 then acc
        else 
            encode_in_log (int lsr 1)
            (SK (Pair [if 1 = (1 land int) then (SK K) else (SK (S K))]
            [acc]))
    in
    if int < 0 then failwith "Illegal argument"
    else encode_in_log int (SK EmptyList)

(* Finally we can do things with sequences *)
let pm_encodings = 
    make_encoder 
    (SK (substitute (delete insert)))
    ["substitute", substitute; "delete", delete; "insert", insert]

(* An example using the previous composable edition functions  *)
let () =
    let do_test = false in
    if do_test then
        let encoder = 
           make_encoder (SK (substitute (insert delete)))
           ["substitute", substitute_composable; "delete", delete_composable;
           "insert", insert_composable] 
        in
        let todo = 
            SKLS K [SKLS K] [encode_in_log 0] [timine] K [SKLS (S K) (S K)]
            [encode_in_log 1]
        in
        let seq = SKLS [adenine] [guanine] [guanine] [guanine] in
        let res = 
            S_K.eval 
            (SK ([apply_list_of_functions_on_accumulator] 
            [seq] [encoder] [todo]))
        in 
        print_endline (S_K.to_string res)
    else ()

let create_sequence a =
    let pair = `Label "Pair" in
    let merge a b = `Node [pair; a; b] in
    let rec prepend pos acc =
        if pos < 0 then acc
        else 
            let npos = pos - 1 in
            match a.[pos] with
            | 'A' | 'a' -> prepend npos (merge adenine acc)
            | 'C' | 'c' -> prepend npos (merge citosine acc)
            | 'G' | 'g' -> prepend npos (merge guanine acc)
            | 'T' | 't' -> prepend npos (merge timine acc)
            | _ -> prepend npos acc
    in
    prepend ((String.length a) - 1) (SK (Pair EmptyList EmptyList))

let generate_editions_machine_from_alignment a b =
    (* We want to produce a machine that given the sequence [a] produces as
    * output the sequence [b]. *)
    assert ((String.length a) = (String.length b));
    let max = String.length a in
    let base = function
        | 'A' | 'a' -> adenine
        | 'C' | 'c' -> citosine
        | 'G' | 'g' -> guanine
        | 'T' | 'U' | 't' | 'u' -> timine
        | '_' -> `Label "Emptylist"
        | _ -> failwith "Illegal DNA sequence"
    in
    let rec compare_and_generate_edition delta position =
        if max = position then []
        else
            let npos = position + 1 in
            if a.[position] = b.[position] then 
                compare_and_generate_edition (delta + 1) npos
            else 
                let deltap = encode_in_log delta 
                and basep = base b.[position] in
                if a.[position] = '_' then
                    (SK K) :: (SKLS (S K) K) :: deltap :: basep ::
                        compare_and_generate_edition 0 npos
                else if b.[position] = '_' then
                    (SK K) :: (SKLS (S K) (S K)) :: deltap ::
                        compare_and_generate_edition 0 npos
                else 
                    (SK K) :: (SKLS K) :: deltap :: basep ::
                        compare_and_generate_edition 0 npos
    in
    let pair = `Label "Pair" in
    let rec produce_list_expression lst = 
        match lst with
        | h :: t -> `Node [pair; h; produce_list_expression t]
        | [] -> `Label "EmptyList"
    in
    produce_list_expression (compare_and_generate_edition 0 0) 

let generate_alignment_machine a b =
    let edition_machine = generate_editions_machine_from_alignment a b 
    and accumulator = create_sequence a 
    and encoder = 
       make_encoder (SK (substitute (insert delete)))
       ["substitute", substitute_composable; "delete", delete_composable;
       "insert", insert_composable] 
    in
    S_K.expand (SK ([apply_list_of_functions_on_accumulator] [accumulator]
    [encoder] [edition_machine]))

let generate_acc_and_edition_machine a b =
    let edition_machine = generate_editions_machine_from_alignment a b 
    and accumulator = create_sequence a in
    S_K.expand edition_machine, S_K.expand accumulator


(* A tree is represented the same as before:
    * An internal node
    * (K ((left_tree, left_editions) (right_tree, right_editions))) 
    * A leaf
    * (EmptyList) *)
let process_tree =
    let recursive_processor =
        let left_editions = SK (tree [u_Tl] [u_Hd] [u_Tl])
        and right_editions = SK (tree [u_Tl] [u_Tl] [u_Tl])
        and left_tree = SK (tree [u_Tl] [u_Hd] [u_Hd])
        and right_tree = SK (Tree [u_Tl] [u_Tl] [u_Hd]) in
        S_K.create 
        (SK ((tree [u_Hd] K K) 
            (* We are in an interior node *)
            (Pair K (Pair (R processor (processor acc encoder [left_editions])
            encoder [left_tree]) (R processor (processor acc encoder [right_editions])
            encoder [right_tree])))
            (* No we are in a leaf *)
            (Pair (K S) acc)))
        (LS processor acc encoder tree)
    in
    S_K.create (SK (Fixedpoint [recursive_processor])) []

(* Now we should be able to take a POY diagnosis and generate the complete
* sequences, right? Let's give it a shot! *)
*)
