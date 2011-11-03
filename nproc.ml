open Printf

let log_error = ref (fun s -> eprintf "[err] %s\n%!" s)
let log_info = ref (fun s -> eprintf "[info] %s\n%!" s)
let string_of_exn = ref Printexc.to_string

let stream_pop x =
  let o = Stream.peek x in
  (match o with
       None -> ()
     | Some _ -> Stream.junk x
  );
  o

let lwt_of_stream x =
  Lwt_stream.from (fun () -> Lwt.return (stream_pop x))

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
(* executed in worker processes, it closes the master side of the pipes
   inherited via fork() *)
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

(* --master-- *)
let pull_task progress_counter in_stream
    progress central_service handle_result worker =
  (* Note: input and output file descriptors are automatically closed 
     when the end of the lwt channel is reached. *)
  let ic = Lwt_io.of_fd ~mode:Lwt_io.input worker.worker_in in
  let oc = Lwt_io.of_fd ~mode:Lwt_io.output worker.worker_out in
  let rec pull () =
    Lwt.bind (Lwt_stream.get in_stream) (
      function
          None -> Lwt.return ()
        | Some x ->
            let req = Worker_req x in
            Lwt.bind
              (write_value oc req)
              read_from_worker
    )
  and read_from_worker () =
    Lwt.bind (Lwt_io.read_value ic) handle_input

  and handle_input = function
      Worker_res result -> Lwt.bind (handle_result result) pull_new
    | Central_req x ->
        Lwt.bind (central_service x) (
          fun y ->
            let res = Central_res y in
            Lwt.bind
              (write_value oc res)
              read_from_worker
        )
  and pull_new () =
    incr progress_counter;
    progress !progress_counter;
    pull ()
  in
  progress !progress_counter;
  pull ()


(* --master-- *)
let iter
    ?(progress = ignore)
    ~nproc
    ~central_service
    ~worker_service
    ~handle_result
    in_stream =
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
               start_worker_loop worker_service out_read in_write;
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
  let progress_counter = ref 0 in
  let jobs =
    Lwt.join 
      (List.map
         (pull_task progress_counter in_stream
            progress central_service handle_result)
         worker_info)
  in
  Lwt.bind jobs (fun () -> Lwt.return !progress_counter)

(* --master-- *)
let simple_iter
    ?progress
    ~nproc
    ~worker_service
    ~handle_result
    in_stream =
  iter
    ?progress
    ~nproc
    ~central_service: (fun () -> Lwt.return ())
    ~worker_service: (fun dummy_serv x -> worker_service x)
    ~handle_result
    in_stream

(* --master-- *)
let sync_iter
    ?progress
    ~nproc
    ~central_service
    ~worker_service
    ~handle_result
    in_stream =
  Lwt_main.run (
    iter
      ?progress
      ~nproc
      ~central_service: (fun x -> Lwt.return (central_service x))
      ~worker_service
      ~handle_result: (fun x -> Lwt.return (handle_result x))
      (lwt_of_stream in_stream)
  )

(* --master-- *)
let simple_sync_iter
    ?progress
    ~nproc
    ~worker_service
    ~handle_result
    in_stream =
  sync_iter
    ?progress
    ~nproc
    ~central_service:(fun () -> ())
    ~worker_service: (fun dummy_serv x -> worker_service x)
    ~handle_result
    in_stream
