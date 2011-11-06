let test1 () =
  let l = Array.to_list (Array.init 1000 (fun i -> i)) in
  let p, t = Nproc.create 100 in
  List.iter (
    fun x ->
      ignore (
        Lwt.bind (Nproc.submit p (fun n -> Unix.sleep 1; (n, -n)) x)
          (fun (x, y) ->
             Lwt.return (Printf.printf "%i -> %i\n%!" x y))
      )
  ) l;
  Lwt_main.run (Nproc.close p)

let test2 () =
  let strm = Stream.from (fun i -> if i < 1000 then Some i else None) in
  Nproc.iter_stream
    ~nproc: 100
    ~f: (fun n -> Unix.sleep 1; (n, -n))
    ~g: (fun (x, y) -> Printf.printf "%i -> %i\n%!" x y)
    strm

let () =
  print_endline "*** test1 ***";
  test1 ();
  print_endline "*** test2 ***";
  test2 ()

