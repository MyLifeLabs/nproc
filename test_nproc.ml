open Printf

let test_error1 () =
  let strm = Stream.from (fun i -> if i < 100 then Some i else None) in
  try
    Nproc.iter_stream
      ~nproc: 8
      ~f: (fun n -> failwith "oops")
      ~g: (fun _ -> assert false)
      strm
  with e ->
    printf "OK - Caught exception as expected: %s\n"
      (Printexc.to_string e)

let test_error2 () =
  let strm = Stream.from (fun i -> if i < 100 then Some i else None) in
  try
    Nproc.iter_stream
      ~nproc: 8
      ~f: (fun n -> -n)
      ~g: (fun n' -> failwith "oops")
      strm
  with e ->
    printf "OK - Caught exception as expected: %s\n"
      (Printexc.to_string e)


let test1 () =
  let l = Array.to_list (Array.init 6 (fun i -> i)) in
  let p, t = Nproc.create 2 in
  List.iter (
    fun x ->
      ignore (
        Lwt.bind (Nproc.submit p (fun n -> Unix.sleep 1; (n, -n)) x)
          (fun (x, y) ->
             Lwt.return (Printf.printf "%i -> %i\n%!" x y))
      )
  ) l;
  Lwt_main.run (Nproc.close p)

let test2 ?granularity () =
  let strm = Stream.from (fun i -> if i < 6 then Some i else None) in
  Nproc.iter_stream
    ~nproc: 2
    ~f: (fun n -> Unix.sleep 1; (n, -n))
    ~g: (fun (x, y) -> Printf.printf "%i -> %i\n%!" x y)
    strm

let () =
  print_endline "*** test error (1) ***";
  test_error1 ();
  print_endline "*** test error (2) ***";
  test_error2 ();
  print_endline "*** test1 ***";
  test1 ();
  print_endline "*** test2 ***";
  test2 ();
  print_endline "*** test2 (granularity = 3) ***";
  test2 ~granularity:3 ()
