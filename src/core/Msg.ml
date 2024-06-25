type master_msg =
  | Worker_task of (string * Problem.t) list (* prover name, problem *)
  | Stop_worker

type worker_msg =
  | Worker_response of {id: int; events: Run_event.t list; partial: bool }
  | Worker_failure of int * exn

type th_msg = Work_done
