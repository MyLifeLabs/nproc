type cache_request =
    Get_req of int
  | Set_req of (int * int)

type cache_response =
    Get_res of int option
  | Set_res

let worker_service cache x =
  let k = x mod 100 in
  let v =
    match cache (Get_req k) with
        Get_res (Some v) -> v
      | Get_res None ->
          let v =
            Unix.sleep 1;
            -x
          in
          assert (cache (Set_req (k, v)) = Set_res);
          v
      | Set_res -> assert false
  in
  (x, v)

let central_service =
  let tbl = lazy (Hashtbl.create 1000) in
  function
      Get_req k ->
        (try Get_res (Some (Hashtbl.find (Lazy.force tbl) k))
         with Not_found -> Get_res None)
    | Set_req (k, v) ->
        Hashtbl.replace (Lazy.force tbl) k v;
        Set_res

let handle_result (x, v) =
  Printf.printf "%i -> %i\n%!" x v

let main () =
  let stream = Stream.from (fun i -> if i < 1000 then Some i else None) in
  Nproc.sync_iter
    ~nproc: 100
    ~central_service
    ~worker_service
    ~handle_result
    stream

let () =
  let n = main () in
  Printf.printf "Processed %i items.\n" n
