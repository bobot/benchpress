
(* run tests, or compare results *)
module T = Test
module E = CCResult

(* TODO: only load full results if needed *)
let main ?(check=true) ?(bad=true) ?csv ?summary (file:string) =
  let open E.Infix in
  Logs.debug (fun k->k "loading file %S..." file);
  Bin_utils.load_file file >>= fun res ->
  Logs.debug (fun k->k "loaded file %S" file);
  Bin_utils.dump_csv ~csv res;
  Bin_utils.dump_summary ~summary res;
  Bin_utils.printbox_results res;
  if bad && not (T.Top_result.is_ok res) then (
    Format.printf "@[<2>bad: %a@]@." T.Top_result.pp_bad res;
  );
  if check then Bin_utils.check_res Notify.nil res else E.return ()


