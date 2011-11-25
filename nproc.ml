open Printf

let log_error = ref (fun s -> eprintf "[err] %s\n%!" s)
let log_info = ref (fun s -> eprintf "[info] %s\n%!" s)
let string_of_exn = ref Printexc.to_string


module Full =
struct
  type worker = {
    worker_pid : int;
    worker_in : Lwt_unix.file_descr;
    worker_out : Lwt_unix.file_descr;
  }

  type ('b, 'c) from_worker =
      Worker_res of 'b
    | Central_req of 'c

  type ('a, 'b, 'c, 'd, 'e) to_worker =
      Worker_req of (('c -> 'd) -> 'e -> 'a -> 'b) * 'a
    | Central_res of 'd

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
  let start_worker_loop worker_data fd_in fd_out =
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
              Worker_req (f, x) -> f central_service worker_data x
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

  type in_t = Obj.t
  type out_t = Obj.t

  type ('a, 'b, 'c) t = {
    stream :
      ((('a -> 'b) -> 'c -> in_t -> out_t) * in_t * (out_t -> unit))
         Lwt_stream.t;
    push :
      (((('a -> 'b) -> 'c -> in_t -> out_t) * in_t * (out_t -> unit))
         option -> unit);
    close : unit -> unit Lwt.t;
    closed : bool ref;
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
        Worker_res result ->
          g result;
          pull ()
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
  let create_gen (in_stream, push) nproc central_service worker_data =
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
                 !log_error (sprintf "Uncaught exception in worker (pid %i): %s"
                               (Unix.getpid ()) (!string_of_exn e));
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
    let jobs =
      Lwt.join 
        (List.map
           (pull_task in_stream central_service)
           worker_info)
    in

    let terminate () =
      Array.iter (
        function
            None -> ()
          | Some x ->
              (try close_worker x with _ -> ());
              (try Unix.kill x.worker_pid Sys.sigkill with _ -> ())
      ) proc_pool
    in

    let closed = ref false in

    let close_stream () =
      if not !closed then (
        push None;
        closed := true;
        Lwt.bind jobs (fun () -> Lwt.return (terminate ()))
      )
      else
        Lwt.return ()
    in
    
    let p = {
      stream = in_stream;
      push = push;
      close = close_stream;
      closed = closed;
    }
    in
    p, jobs

  let create nproc central_service worker_data =
    create_gen (Lwt_stream.create ()) nproc central_service worker_data

  let close p =
    p.close ()

  let submit p ~f x =
    if !(p.closed) then
      Lwt.fail (Failure
                  ("Cannot submit task to process pool because it is closed"))
    else
      let waiter, wakener = Lwt.task () in
      let handle_result y = Lwt.wakeup wakener y in
      p.push (Some (Obj.magic f, Obj.magic x, Obj.magic handle_result));
      waiter

  let stream_pop x =
    let o = Stream.peek x in
    (match o with
         None -> ()
       | Some _ -> Stream.junk x
    );
    o
      
  let lwt_of_stream f g strm =
    Lwt_stream.from (
      fun () ->
        let elt =
          match stream_pop strm with
              None -> None
            | Some x -> Some (Obj.magic f, Obj.magic x, Obj.magic g)
        in
        Lwt.return elt
    )

  let iter_stream ~nproc ~serv ~env ~f ~g in_stream =
    let task_stream = lwt_of_stream f g in_stream in
    let p, t =
      create_gen (task_stream, (fun _ -> assert false)) nproc serv env
    in
    Lwt_main.run t
end


type t = (unit, unit, unit) Full.t

let create n =
  Full.create n (fun () -> Lwt.return ()) ()

let close = Full.close

let submit p ~f x =
  Full.submit p (fun _ _ x -> f x) x

let iter_stream ~nproc ~f ~g strm =
  Full.iter_stream
    ~nproc
    ~env: ()
    ~serv: (fun () -> Lwt.return ())
    ~f: (fun serv env x -> f x)
    ~g
    strm
