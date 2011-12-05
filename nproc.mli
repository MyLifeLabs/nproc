(** Process pools *)

(**
   A process pool is a fixed set of processes that perform 
   arbitrary computations for a master process, in parallel
   and without blocking the master.

   Master and workers communicate by message-passing. The implementation
   relies on fork, pipes, Marshal and {{:http://ocsigen.org/lwt/manual/}Lwt}.

   Error handling:
   - Functions passed by the user to Nproc should not raise exceptions.
   - Exceptions raised accidentally by user-given functions
     either in the master or in the workers are logged but not propagated
     as exceptions. The result of the call uses the [option] type
     and [None] indicates that an exception was caught.
   - Exceptions due to bugs in Nproc hopefully won't occur often 
     but if they do they will be handled just like user exceptions.
   - Fatal errors occurring in workers result in the
     termination of the master and all the workers. Such errors include
     segmentation faults, sigkills sent by other processes,
     explicit calls to the exit function, etc.

   Logging:
   - Nproc logs error messages as well as informative messages
     that it judges useful and affordable in terms of performance.
   - The printing functions [log_error] and [log_info]
     can be redefined to take advantage of a particular logging system.
   - No logging takes place in the worker processes.
   - Only the function that converts exceptions into strings [string_of_exn]
     may be called in both master and workers.
*)

type t
  (** Type of a process pool *)

type worker_info = private {
  worker_id : int;
    (** Worker identifier ranging between 0 and (number of workers - 1). *)

  worker_loop : 'a. unit -> 'a;
    (** Function that starts the worker's infinite loop. *)
}

exception Start_worker of worker_info
  (** This is the only exception that may be raised by the user from within
      the [init] function passed as an option to {!Nproc.create}.
      In this case it is the user's responsibility to catch the exception
      and to start the worker loop.

      The purpose of this exception is to allow the user to clear
      the call stack in the child processes, allowing
      the garbage collector to free up heap-allocated memory that
      would otherwise be wasted.
  *)

val create :
  ?init: (worker_info -> unit) ->
  int -> t * unit Lwt.t
  (** Create a process pool.

      [create nproc] returns [(ppool, lwt)] where
      [ppool] is a pool of [nproc] processes and [lwt] is a lightweight thread
      that finishes when the pool is closed.

      @param init initialization function called at the beginning of
                  of each worker process. By default it does nothing.
                  Specifying a custom [init] function allows to perform
                  some initial cleanup of resources
                  inherited from the parent (master),
                  such as closing files or connections. It may also 
                  raise the {!Nproc.Start_worker} exception as a means
                  of clearing the call stack inherited from the parent,
                  enabling the garbage collection of some useless data.
                  If this [Start_worker] mechanism is used,
                  the [worker_loop] function from the {!Nproc.worker_info}
                  record needs to be called explicitly after catching
                  the exception.
  *)

val close : t -> unit Lwt.t
  (** Close a process pool.
      It waits for all submitted tasks to finish. *)

val terminate : t -> unit
  (** Terminate the processes of a pool without waiting for the pending
      tasks to complete. *)

val submit :
  t -> f: ('a -> 'b) -> 'a -> 'b option Lwt.t
  (** Submit a task.
      [submit ppool ~f x] passes [f] and [x] to one of the worker processes,
      which computes [f x] and passes the result back to the master process,
      i.e. to the calling process running the Lwt event loop.
  
      The current implementation uses the Marshal module to serialize
      and deserialize [f], its input and its output.
  *)

val iter_stream :
  ?granularity: int ->
  ?init: (worker_info -> unit) ->
  nproc: int ->
  f: ('a -> 'b) ->
  g: ('b option -> unit) ->
  'a Stream.t -> unit
  (**
     Iterate over a stream using a pool of 
     [nproc] worker processes running in parallel.

     [iter_stream] runs the Lwt event loop internally. It is intended
     for programs that do not use Lwt otherwise.

     Function [f] runs in the worker processes. It is applied to elements 
     of the stream that it receives from the master process.
     Function [g] is applied to the result of [f] in the master process.

     The current implementation uses the Marshal module to serialize
     and deserialize [f], its inputs (stream elements) and its outputs.
     [f] is serialized as many times as there are elements in the stream.
     If [f] relies on a large immutable data structure, we recommend
     using the [env] option of [Full.iter_stream].

     @param granularity allows to improve the performance of short-lived
                        tasks by grouping multiple tasks internally into 
                        a single task.
                        This reduces the overhead of the underlying
                        message-passing system but makes the tasks
                        sequential within each group.
                        The default [granularity] is 1.

     @param init see {!Nproc.create}.
  *)

val log_error : (string -> unit) ref
  (** Function used by Nproc for printing error messages.
      By default it writes a message to the [stderr] channel
      and flushes its buffer. *)

val log_info : (string -> unit) ref
  (** Function used by Nproc for printing informational messages.
      By default it writes a message to the [stderr] channel
      and flushes its buffer. *)

val string_of_exn : (exn -> string) ref
  (** Function used by Nproc to convert exception into a string used
      in error messages.
      By default it is set to [Printexc.to_string].
      Users might want to change it into a function that prints
      a stack backtrace, e.g.
{v
Nproc.string_of_exn :=
  (fun e -> Printexc.get_backtrace () ^ Printexc.to_string e)
v}
  *)

(** Fuller interface allowing requests from a worker to the master
    and environment data residing in the workers. *)
module Full :
sig
  type ('serv_request, 'serv_response, 'env) t
    (**
       Type of a process pool.
       The type parameters correspond to the following:
       - ['serv_request]: type of the requests from worker to master,
       - ['serv_response]: type of the responses to the requests,
       - ['env]: type of the environment data passed just once to each
         worker process.
    *)

  val create :
    ?init: (worker_info -> unit) ->
    int ->
    ('serv_request -> 'serv_response Lwt.t) ->
    'env ->
    ('serv_request, 'serv_response, 'env) t * unit Lwt.t
      (** Create a process pool.
          [create nproc service env] returns [(ppool, lwt)] where
          [ppool] is pool of [nproc] processes and [lwt] is a
          lightweight thread that finishes when the pool is closed.

          [service] is a service which is run asynchronously by the
          master process and can be called synchronously by the workers.

          [env] is arbitrary environment data, typically large, that
          is passed to the workers just once during their initialization.

          @param init see {!Nproc.create}.
      *)

  val close :
    ('serv_request, 'serv_response, 'env) t -> unit Lwt.t
    (** Close a process pool.
        It waits for all submitted tasks to finish. *)

  val terminate :
    ('serv_request, 'serv_response, 'env) t -> unit
    (** Terminate the processes of a pool without waiting for the pending
        tasks to complete. *)

  val submit :
    ('serv_request, 'serv_response, 'env) t ->
    f: (('serv_request -> 'serv_response) -> 'env -> 'a -> 'b) ->
    'a -> 'b option Lwt.t
    (** Submit a task.
        [submit ppool ~f x] passes [f] and [x] to one of the worker processes,
        which computes [f service env x] and passes the result back
        to the master process,
        i.e. to the calling process running the Lwt event loop.
  
        The current implementation uses the Marshal module to serialize
        and deserialize [f], its input and its output.
    *)

  val iter_stream :
    ?granularity: int ->
    ?init: (worker_info -> unit) ->
    nproc: int ->
    serv: ('serv_request -> 'serv_response Lwt.t) ->
    env: 'env ->
    f: (('serv_request -> 'serv_response) -> 'env -> 'a -> 'b) ->
    g: ('b option -> unit) ->
    'a Stream.t -> unit
    (**
       Iterate over a stream using a pool of 
       [nproc] worker processes running in parallel.

       [iter_stream] runs the Lwt event loop internally. It is intended
       for programs that do not use Lwt otherwise.

       Function [f] runs in the worker processes. It is applied to elements 
       of the stream that it receives from the master process.
       Function [g] is applied to the result of [f] in the master process.

       The current implementation uses the Marshal module to serialize
       and deserialize [f], its inputs (stream elements) and its outputs.
       [f] is serialized as many times as there are elements in the stream.
       If [f] relies on a large immutable data structure, it should be
       putting into [env] in order to avoid costly and
       repetitive serialization of that data.

       @param init see {!Nproc.create}.
    *)

end
