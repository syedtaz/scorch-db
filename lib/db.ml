open Core
include Db_intf

module Make (S : Serializable) : DB with type key = S.key and type value = S.value =
struct
  type key = S.key
  type value = S.value

  module Memtable = Machine.Memtable.Make (S)
  module Log = Machine.Log.Make (S)
  module Bootstrap = Machine.Bootstrap.Make (S)

  type t =
    { fd : Core_unix.File_descr.t
    ; mutable machine :
        ( (key, value) Machine.Memtable_intf.event
          , (key, value) Machine.Log_intf.response )
          Kernel.Mealy.s
    }

  let debug_msg msgs =
    let keyf k = S.sexp_of_key k |> Sexp.to_string_hum in
    List.iter msgs ~f:(function
      | `Delete k -> Format.printf "Delete %s.\n" (keyf k)
      | `Insert (k, _) -> Format.printf "Insert %s with some value.\n" (keyf k))
  ;;

  let open_db path : (t, [> `Cannot_determine ]) result =
    let msgs = Bootstrap.generate_msgs path in
    debug_msg msgs;
    let machine =
      Kernel.Mealy.( >>> ) (Memtable.from_msgs msgs) (Log.machine path)
      |> Kernel.Mealy.unfold
    in
    match Sys_unix.file_exists ~follow_symlinks:true path with
    | `Unknown -> Error `Cannot_determine
    | `Yes -> Ok { fd = Core_unix.openfile ~mode:[ O_RDWR ] path; machine }
    | `No ->
      let dirname = Filename.dirname path in
      Core_unix.mkdir_p dirname;
      Ok { fd = Core_unix.openfile ~mode:[ O_CREAT; O_RDWR ] path; machine }
  ;;

  let close_db (db : t) : unit = Core_unix.close db.fd

  let ( >>/ ) (db : t) event =
    let res, ns = db.machine.action event in
    db.machine <- ns;
    res
  ;;

  let get db key =
    match db >>/ `Get key with
    | SuccessValue v -> Ok v
    | _ -> Error `Cannot_determine
  ;;

  let insert db ~key ~value =
    match db >>/ `Insert (key, value) with
    | SuccessValue v -> Ok v
    | _ -> Error `Cannot_determine
  ;;

  let delete db key =
    match db >>/ `Delete key with
    | SuccessValue v -> Ok v
    | _ -> Error `Cannot_determine
  ;;

  let update_fetch db key ~f =
    match db >>/ `UpdateFetch (key, f) with
    | SuccessValue v -> Ok v
    | _ -> Error `Cannot_determine
  ;;

  let fetch_update db key ~f =
    match db >>/ `FetchUpdate (key, f) with
    | SuccessValue v -> Ok v
    | _ -> Error `Cannot_determine
  ;;
end
