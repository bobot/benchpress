(** Stanzas for the configuration language *)

open Common
module Se = Sexp_loc

type loc = Loc.t

(** Result to expect for a problem *)
type expect =
  | E_const of Res.t
  | E_program of { prover: string }
  | E_try of expect list  (** Try these methods successively *)

type version_field =
  | Version_exact of Prover.version
  | Version_git of { dir: string } (* compute by calling git *)
  | Version_cmd of { cmd: string }

type stack_limit = Unlimited | Limited of int

type regex = string
(** A regex in Perl syntax *)

type git_fetch = GF_fetch | GF_pull

type slurm_info = {
  partition: string option;
  (* The partition to which the allocated nodes should belong. *)
  additional_options: string list;
  (* Additional options for sbatch. *)
  nodes: int option;
  (* the maximum number of nodes that can be allocated for the job.
     One worker will run per node *)
  addr: Unix.inet_addr option;
  (* IP address of the server on the control node.
     Needs to be reachable by the workers which will run on the allocated calculation nodes. *)
  port: int option;
  (* port of the server in the control node. *)
}

type action =
  | A_run_provers of {
      j: int option;
      dirs: string list; (* list of directories to examine *)
      dir_files: string list;
          (* list of files containing directories, as in option -F *)
      pattern: regex option;
      provers: string list;
      timeout: int option;
      memory: int option;
      stack: stack_limit option;
      loc: Loc.t;
    }
  | A_run_provers_slurm of {
      j: int option;
      dirs: string list; (* list of directories to examine *)
      dir_files: string list;
          (* list of files containing directories, as in option -F *)
      pattern: regex option;
      provers: string list;
      timeout: int option;
      memory: int option;
      stack: stack_limit option;
      slurm: slurm_info;
      ntasks: int option;
      loc: Loc.t;
    }
  | A_git_checkout of {
      dir: string;
      ref: string;
      fetch_first: git_fetch option;
      loc: Loc.t;
    }
  | A_run_cmd of { cmd: string; loc: Loc.t }
  | A_progn of action list

(** Stanzas for the configuration *)
type t =
  | St_enter_file of string
  | St_prover of {
      name: string;
      loc: Loc.t;
      version: version_field option;
      binary: string option;
          (** Path to the binary to use.  Useful in combination with [inherits] *)
      cmd: string option;
          (** the command line to run.
          possibly contains $binary, $file, $memory and $timeout,
          and $proof_file if {!produces_proof} is true *)
      produces_proof: bool option;
          (** true if the solver should be passed $proof_file into which
          it can emit a proof *)
      proof_ext: string option;  (** file extension for proofs *)
      proof_checker: string option;  (** name of proof checker *)
      ulimits: Ulimit.conf option;  (** which limits to enforce using ulimit *)
      (* Result analysis *)
      unsat: regex option;  (** regex for "unsat" *)
      sat: regex option;  (** regex for "sat" *)
      unknown: regex option;  (** regex for "unknown" *)
      timeout: regex option;  (** regex for "timeout" *)
      memory: regex option;  (** regex for "out of memory" *)
      custom: (string * regex) list;  (** regex for custom results *)
      inherits: string option;  (** Inherit another prover definition *)
    }
  | St_proof_checker of {
      name: string;
      loc: Loc.t;
      cmd: string;
      (* results *)
      valid: regex;  (** regex for valid proofs *)
      invalid: regex;  (** regex for invalid proofs *)
    }
  | St_dir of {
      name: string option;
      path: string;
      expect: expect option;
      pattern: regex option;  (** Pattern of problems in this directory *)
      loc: Loc.t;
    }
  | St_task of {
      name: string; (* name of this task *)
      synopsis: string option;
      action: action;
      loc: Loc.t;
    }
  | St_set_options of { progress: bool option; j: int option; loc: Loc.t }
  | St_declare_custom_tag of { tag: string; loc: Loc.t }
  | St_error of { err: Error.t; loc: Loc.t }

val pp_expect : expect Fmt.printer
val pp_version_field : version_field Fmt.printer
val pp_git_fetch : git_fetch Fmt.printer
val pp_stack_limit : stack_limit Fmt.printer
val pp_action : action Fmt.printer
val pp : t Fmt.printer
val pp_l : t list Fmt.printer
val as_error : t -> Error.t option
val errors : t list -> Error.t list

(** {2 Decoding} *)

val parse_files : ?reify_errors:bool -> string list -> t list
(** Parse a list of files and return their concatenated stanzas.
    @param builtin if true, add the builtin prelude before the files
    @param reify_errors if true, parsing errors become {!St_error}
*)

val parse_string : ?reify_errors:bool -> filename:string -> string -> t list
(** Parse a string. See {!parse_files} for the arguments.
    @param filename name used in locations *)

val prover_wl_to_st : Prover.t With_loc.t -> t
val proof_checker_wl_to_st : Proof_checker.t With_loc.t -> t
