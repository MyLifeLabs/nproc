val lwt_of_stream : 'a Stream.t -> 'a Lwt_stream.t
  (** This function builds an Lwt stream from a regular stream.

      Note about Lwt streams in general:

      Lwt streams are quite different from regular streams. They can
      be in three different states:

      1. empty, i.e. no element will ever be retrieved from that stream
      2. not empty with some element immediately available
      3. not empty with no element immediately available

      The third state won't exist with an Lwt stream created by
      this function [lwt_of_stream] but can be created using 
      [Lwt_stream.create ()], which returns a stream and a [push] function.
      The [push] function puts elements into the stream or sets the
      end of the stream by adding [None].

      Functions like [Lwt_stream.get] create a lightweight thread that
      will wait until either some value is available (added by some other
      thread using [push]) or the end of the stream is reached.
      Similarly, [Lwt_stream.is_empty] does not return a [bool]
      directly but a [bool Lwt.t] because it needs to wait until
      the stream is either in state 1 (true) or in state 2 (false).
  *)

val iter :
  ?progress: (int -> unit) ->
  nproc: int ->
  central_service:
    ('central_req -> 'central_res Lwt.t) ->
  worker_service:
    (('central_req -> 'central_res) -> 'worker_req -> 'worker_res) ->
  handle_result:
    ('worker_res -> unit Lwt.t) ->
  'worker_req Lwt_stream.t -> int Lwt.t

val simple_iter :
  ?progress: (int -> unit) ->
  nproc: int ->
  worker_service: ('worker_req -> 'worker_res) ->
  handle_result: ('worker_res -> unit Lwt.t) ->
  'worker_req Lwt_stream.t -> int Lwt.t
  (** Iterate over a stream, delegating the computations to a pool of [nproc]
      processes. This takes place within the Lwt event loop. *)

val sync_iter :
  ?progress: (int -> unit) ->
  nproc: int ->
  central_service:
    ('central_req -> 'central_res) ->
  worker_service:
    (('central_req -> 'central_res) -> 'worker_req -> 'worker_res) ->
  handle_result:
    ('worker_res -> unit) ->
  'worker_req Stream.t -> int
  (**
     Same as [iter] but launches and completes the Lwt event loop internally.

     No knowledge of Lwt is required, but since this launches Lwt's
     event loop, [sync_iter] can't be called from within an existing 
     Lwt event loop.
  *)

val simple_sync_iter :
  ?progress: (int -> unit) ->
  nproc: int ->
  worker_service: ('worker_req -> 'worker_res) ->
  handle_result: ('worker_res -> unit) ->
  'worker_req Stream.t -> int

val log_error : (string -> unit) ref
val log_info : (string -> unit) ref
val string_of_exn : (exn -> string) ref
