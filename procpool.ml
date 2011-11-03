module Full =
struct
  type worker = {
    worker_pid : int;
    worker_in : Lwt_unix.file_descr;
    worker_out : Lwt_unix.file_descr;
  }

  type ('a, 'b) from_worker =
      Central_req of 'a
    | Worker_res of 'b

  type ('a, 'b) to_worker =
      Central_res of 'a
    | Worker_req of 'b

  (* --worker-- *)
  (* executed in worker processes right after the fork or in 
     the master when closing the process pool.
     It closes the master side of the pipes. *)
  let close_worker x =
    Unix.close (Lwt_unix.unix_file_descr x.worker_in);
    Unix.close (Lwt_unix.unix_file_descr x.worker_out)

  (* --worker-- *)
  let cleanup_proc_pool a =
    for i = 0 to Array.length a - 1 do
      match a.(i) with
          None -> ()
        | Some x ->
            close_worker x;
            a.(i) <- None
    done

  (* --worker-- *)
  let start_worker_loop worker_service fd_in fd_out =
    let ic = Unix.in_channel_of_descr fd_in in
    let oc = Unix.out_channel_of_descr fd_out in
    let central_service x =
      Marshal.to_channel oc (Central_req x) [Marshal.Closures];
      flush oc;
      match Marshal.from_channel ic with
          Central_res y -> y
        | Worker_req _ -> assert false
    in
    while true do
      let result =
        try
          match Marshal.from_channel ic with
              Worker_req x -> worker_service central_service x
            | Central_res _ -> assert false
        with
            End_of_file ->
              exit 0
      in
      try
        Marshal.to_channel oc (Worker_res result) [Marshal.Closures];
        flush oc
      with Sys_error "Broken pipe" ->
        exit 0
    done

  let write_value oc x =
    Lwt.bind
      (Lwt_io.write_value oc ~flags:[Marshal.Closures] x)
      (fun () -> Lwt_io.flush oc)

  type ('a, 'b, 'c) t = {
    stream :
      'd. ((('a -> 'b) -> 'c -> 'd) * ('d -> unit)) Lwt_stream.t;
    push :
      'd. (((('a -> 'b) -> 'c -> 'd) * ('d -> unit)) option -> unit);
    close : unit -> unit;
  }

  (* --master-- *)
  let pull_task in_stream central_service worker =
    (* Note: input and output file descriptors are automatically closed 
       when the end of the lwt channel is reached. *)
    let ic = Lwt_io.of_fd ~mode:Lwt_io.input worker.worker_in in
    let oc = Lwt_io.of_fd ~mode:Lwt_io.output worker.worker_out in
    let rec pull () =
      Lwt.bind (Lwt_stream.get in_stream) (
        function
            None -> Lwt.return ()
          | Some (f, x, g) ->
              let req = Worker_req (f, x) in
              Lwt.bind
                (write_value oc req)
                (read_from_worker g)
      )
    and read_from_worker g () =
      Lwt.bind (Lwt_io.read_value ic) (handle_input g)
        
    and handle_input g = function
        Worker_res result -> Lwt.bind (g result) pull
      | Central_req x ->
          Lwt.bind (central_service x) (
            fun y ->
              let res = Central_res y in
              Lwt.bind
                (write_value oc res)
                (read_from_worker g)
          )
    in
    pull ()

  (* --master-- *)
  let create nproc central_service worker_data =
    let proc_pool = Array.make nproc None in
    Array.iteri (
      fun i _ ->
        let (in_read, in_write) = Lwt_unix.pipe_in () in
        let (out_read, out_write) = Lwt_unix.pipe_out () in
        match Unix.fork () with
            0 ->
              (try
                 Unix.close (Lwt_unix.unix_file_descr in_read);
                 Unix.close (Lwt_unix.unix_file_descr out_write);
                 cleanup_proc_pool proc_pool;
                 start_worker_loop worker_data out_read in_write;
               with e ->
                 Log.logf `Crit "Uncaught exception in worker (pid %i): %s"
                   (Unix.getpid ()) (Exn.to_string e);
                 exit 1
              )
          | child_pid ->
              Unix.close in_write;
              Unix.close out_read;
              proc_pool.(i) <-
                Some {
                  worker_pid = child_pid;
                  worker_in = in_read;
                  worker_out = out_write;
                }
    ) proc_pool;

    (*
      Create nproc lightweight threads.
      Each lightweight thread pull tasks from the stream and feeds its worker
      until the stream is empty.
    *)
    let worker_info =
      Array.to_list
        (Array.map (function Some x -> x | None -> assert false) proc_pool)
    in
    let in_stream, push = Lwt_stream.create () in
    let jobs =
      Lwt.join 
        (List.map
           (pull_task in_stream central_service)
           worker_info)
    in

    let closed = ref false in

    let close () =
      if not !closed then (
        Array.iter (
          function
              None -> ()
            | Some x ->
                (try close_worker x with _ -> ());
                (try Unix.kill x.worker_pid Sys.sigkill with _ -> ())
        ) proc_pool;
        closed := true
      )
    in

    let p = {
      stream = in_stream;
      push = push;
      close = close;
    }
    in
    Lwt.bind jobs (fun () -> Lwt.return p)

  let close p =
    p.close ()

  let submit p f g x =
    p.push p.stream (Some (f, x, g))
end


type t = (unit, unit, unit) Full.t

let create n =
  Full.create n (fun () -> Lwt.return ())

let submit p f g x =
  Full.submit p (fun _ x -> f x) g x
