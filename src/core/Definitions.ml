(* This file is free software. See file "license" for more details. *)

(** {1 Definitions} *)

module E = CCResult
module Fmt = CCFormat
module Str_map = Misc.Str_map

type path = string
type 'a or_error = ('a, string) Result.result

open E.Infix

type def =
  | D_prover of Prover.t
  | D_task of Task.t

(** All known definitions *)
type t = {
  defs: def Str_map.t;
  dirs: Dir.t list; (* list of directories *)
}

let empty : t = { defs= Str_map.empty; dirs=[]}

let add_prover (p:Prover.t) self : t =
  { self with defs=Str_map.add (Prover.name p) (D_prover p) self.defs}

let add_task (t:Task.t) self : t =
  { self with defs=Str_map.add t.Task.name (D_task t) self.defs}

let add_dir (d:Dir.t) self : t =
  { self with dirs=d::self.dirs }

(* compute a version for the prover *)
let get_version ?(binary="") (v:Stanza.version_field) : Prover.version =
  let open Prover in
  begin match v with
    | Stanza.Version_git {dir} ->
      Git {branch=Misc.Git.get_branch dir; commit=Misc.Git.get_commit dir}
    | Stanza.Version_cmd {cmd} ->
      begin try
          Tag (Misc.get_cmd_out @@ Prover.interpolate_cmd ~binary cmd)
        with Prover.Subst_not_found s ->
          Tag (Printf.sprintf "command `%s` failed: cannot find field %s" cmd s)
      end
    | Stanza.Version_exact v -> v
  end

(* TODO: deprecate and remove once  there are no more toml files *)
(* recover description of prover from config file *)
let build_from_config config pname : Prover.t or_error =
  let open Prover in
  let getter =
    let open Config in
    let prover_tbl = table pname in
    prover_tbl |>> string "cmd" >|= String.trim >>= fun cmd ->
    begin
      (prover_tbl |>> string "binary")
      <|>
        ( let b, _ = CCString.Split.left_exn ~by:" " cmd in
          if b = "$binary" then
            fail ("please provide $binary value for prover " ^ pname)
          else pure b)
    end >>= fun binary ->
    (prover_tbl |>> string_list "binary_deps" <|> pure [])
    >>= fun binary_deps ->
    begin
      (prover_tbl |>> string "version" >|= fun s ->
       get_version ~binary (Stanza.Version_exact (Tag s)))
      <|> pure (Tag "dev")
    end >>= fun version ->
    let get_stropt pname =
      some (prover_tbl |>> string pname) <|> pure None
    in
    get_stropt "unsat" >>= fun unsat ->
    get_stropt "sat" >>= fun sat ->
    get_stropt "timeout" >>= fun timeout ->
    get_stropt "unknown" >>= fun unknown ->
    get_stropt "memory" >>= fun memory ->
    pure {
      name=pname; version; cmd; binary; binary_deps; unsat; sat;
      unknown; timeout; memory; }
  in
  Config.get config getter

(* TODO: deprecate and remove once  there are no more toml files *)
(* make a list of provers from the given config *)
let of_config config : t or_error =
  let open E.Infix in
  begin
    Config.(get_or ~default:[] config @@ string_list "provers")
    |> List.map (build_from_config config)
    |> E.map_l CCFun.id
  end
  >|= fun l ->
  List.fold_left
    (fun map prover -> add_prover prover map)
    empty l

let find_prover self name : Prover.t or_error =
  match Str_map.get name self.defs with
  | Some (D_prover p) -> Ok p
  | Some _ -> E.fail_fprintf "%S is not a prover" name
  | _ -> E.fail_fprintf "prover %S not defined" name

let find_task self name : Task.t or_error =
  match Str_map.get name self.defs with
  | Some (D_task p) -> Ok p
  | Some _ -> E.fail_fprintf "%S is not a task" name
  | _ -> E.fail_fprintf "task %S is not defined" name

let norm_path s =
  s |> Xdg.interpolate_home |> Misc.mk_abs_path

(* find a known directory for [path] *)
let mk_subdir self path : Subdir.t or_error =
  let path = norm_path path in
  (* helper *)
  let is_parent (dir:string) (f:string) : bool =
    let fd_dir = (Unix.stat dir).Unix.st_dev in
    let same_file f = (Unix.stat f).Unix.st_dev = fd_dir in
    (* check f and its parents *)
    let rec check f =
      same_file f ||
      (let parent = Filename.dirname f in
       parent <> f && check parent)
    in
    check f
  in
  CCList.find_map
    (fun dir ->
       Misc.Debug.debugf 3 (fun k->k"check prefix dir=%S for %S" dir.Dir.path path);
       if is_parent dir.Dir.path path
       then Some {Subdir.path; inside=dir}
       else None)
    self.dirs
  |> CCOpt.to_result_lazy
    (fun () -> Printf.sprintf "no known directory contains path %S" path)

let rec conv_expect self = function
  | Stanza.E_const r -> Ok (Dir.E_const r)
  | Stanza.E_program {prover} ->
    find_prover self prover >|= fun p -> Dir.E_program {prover=p}
  | Stanza.E_try l -> E.map_l (conv_expect self) l >|= fun l -> Dir.E_try l

let mk_run_provers ?j ?timeout ?memory ~paths ~provers (self:t) : _ or_error =
  E.map_l (find_prover self) provers >>= fun provers ->
  E.map_l (mk_subdir self) paths >>= fun dirs ->
  let act={
    Action.j; timeout; memory; dirs; provers;
  } in
  Ok act

let mk_action (self:t) (a:Stanza.action) : _ or_error =
  match a with
  | Stanza.A_run_provers {provers; memory; dirs; timeout } ->
    mk_run_provers ?timeout ?memory ~paths:dirs ~provers self
    >|= fun a -> Action.Act_run_provers a

let add_stanza (st:Stanza.t ) self : t or_error =
  Misc.Debug.debugf 5 (fun k->k "add-stanza %a" Stanza.pp st);
  let open Stanza in
  match st with
  | St_dir {path;expect;pattern} ->
    let path = norm_path path in
    (if Sys.file_exists path && Sys.is_directory path then Ok ()
     else E.fail_fprintf "%S is not a directory" path) >>= fun () ->
    begin match expect with
      | None -> Ok Dir.E_comment
      | Some e -> conv_expect self e
    end >>= fun expect ->
    let d = {Dir.path; expect; pattern} in
    Ok (add_dir d self)
  | St_prover {
      name; cmd; sat; unsat; timeout; unknown; memory;
      version; binary; binary_deps;
    } ->
    (* add prover *)
    let binary =
      CCOpt.get_lazy
        (fun () -> fst @@ CCString.Split.left_exn ~by:" " @@ String.trim cmd)
        binary
    and version = match version with
      | Some v -> v
      | None -> Version_exact (Prover.Tag "<unknown>")
    in
    let p = {
      Prover.
      name; cmd; sat; unsat; timeout; unknown; memory; binary; binary_deps;
      version=get_version ~binary version;
    } in
    Ok (add_prover p self)
  | St_task {name; synopsis; action; } ->
    mk_action self action >>= fun action ->
    let t = {Task.name; synopsis; action; } in
    Ok (add_task t self)

let add_stanza_l (l:Stanza.t list) self : t or_error =
  E.fold_l (fun self st -> add_stanza st self) self l

let of_stanza_l l = add_stanza_l l empty

