open Core

module Reader : sig
  type t

  val create : string -> t
  val compact : t -> Action.t list
  val close : t -> unit
end = struct
  type t = { fd : In_channel.t }

  let create path = { fd = In_channel.create path }

  let readline reader =
    let open Option.Let_syntax in
    let%bind line = In_channel.input_line reader.fd in
    return (Yojson.Basic.from_string line)
  ;;

  let update_tbl (action : Action.t) tbl =
    match action with
    | Put { key; _ } | Delete { key } ->
      Hashtbl.find_and_call
        tbl
        key
        ~if_found:(fun _ -> Hashtbl.update tbl key ~f:(fun _ -> action))
        ~if_not_found:(fun _ -> Hashtbl.add_exn tbl ~key ~data:action)
  ;;

  let compact reader =
    let _ = In_channel.input_line reader.fd in
    let rec foldline reader tbl =
      match readline reader with
      | Some v ->
        update_tbl (Action.of_json_exn v) tbl;
        foldline reader tbl
      | None -> tbl
    in
    let results = foldline reader (Hashtbl.create (module String)) in
    List.map ~f:(fun (_, value) -> value) (Hashtbl.to_alist results)
  ;;

  let close reader = In_channel.close reader.fd
end

include Reader