open Printf

let exception_in_f () =
  let n = 100 in
  let strm = Stream.from (fun i -> if i < n then Some i else None) in
  let error_count = ref 0 in
  Nproc.iter_stream
    ~nproc: 8
    ~f: (fun x -> if x = 50 then failwith "raised from f")
    ~g: (function None -> incr error_count | Some _ -> ())
    strm;
  assert (!error_count = 1)

let exception_in_g () =
  let n = 100 in
  let strm = Stream.from (fun i -> if i < n then Some i else None) in
  let real_error_count = ref 0 in
  Nproc.iter_stream
    ~nproc: 8
    ~f: (fun n -> -n)
    ~g: (function
             Some x -> if x = -50 then failwith "raised from g"
           | None -> incr real_error_count)
    strm;
  assert (!real_error_count = 0)

let fatal_exit_in_f () =
  let n = 100 in
  let strm = Stream.from (fun i -> if i < n then Some i else None) in
  let error_count = ref 0 in
  Nproc.iter_stream
    ~nproc: 8
    ~f: (fun x -> if x = 50 then exit 1)
    ~g: (fun _ -> incr error_count)
    strm;
  assert (!error_count = 0);
  assert false

let test_lwt_interface () =
  let l = Array.to_list (Array.init 300 (fun i -> i)) in
  let p, t = Nproc.create 100 in
  let acc = ref [] in
  let error_count1 = ref 0 in
  let error_count2 = ref 0 in
  List.iter (
    fun x ->
      ignore (
        Lwt.bind (Nproc.submit p (fun n -> Unix.sleep 1; (n, -n)) x)
          (function
               Some (x, y) ->
                 if y <> -x then
                   incr error_count1;
                 acc := y :: !acc;
                 Lwt.return ()
             | None ->
                 incr error_count2;
                 Lwt.return ()
          )
      )
  ) l;
  Lwt_main.run (Nproc.close p);
  assert (!error_count1 = 0);
  assert (!error_count2 = 0);
  assert (List.sort compare (List.map (~-) !acc) = l)

let within mini maxi x =
  x >= mini && x <= maxi

let timed mini maxi f =
  let t1 = Unix.gettimeofday () in
  f ();
  let t2 = Unix.gettimeofday () in
  let dt = t2 -. t1 in
  printf "total time: %.6fs\n%!" dt;
  dt >= mini && dt <= maxi

let test_stream_interface_gen granularity () =
  let l = Array.to_list (Array.init 300 (fun i -> i)) in
  let strm = Stream.of_list l in
  let error_count = ref 0 in
  let acc = ref [] in
  Nproc.iter_stream
    ~granularity
    ~nproc: 100
    ~f: (fun n -> Unix.sleep 1; (n, -n))
    ~g: (function Some (x, y) -> acc := y :: !acc | None -> incr error_count)
    strm;
  assert (!error_count = 0);
  assert (List.sort compare (List.map (~-) !acc) = l)

let test_stream_interface () =
  assert (timed 2.99 3.20 (test_stream_interface_gen 1))

let test_stream_interface_g10 () =
  assert (timed 9.99 10.20 (test_stream_interface_gen 10))

let run name f =
  printf "[%s]\n%!" name;
  f ();
  printf "OK\n%!"

let tests =
  [
    ("exception in f", exception_in_f);
    ("exception in g", exception_in_g);
    (*("fatal exit in f", fatal_exit_in_f);*)
    ("lwt interface", test_lwt_interface);
    ("stream interface", test_stream_interface);
    ("stream interface with granularity=10", test_stream_interface_g10);
  ]

let main () = List.iter (fun (name, f) -> run name f) tests

let () = main ()
