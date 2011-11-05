let main () =
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

let () = main ()
