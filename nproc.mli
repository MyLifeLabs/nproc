type t
val create : int -> t * unit Lwt.t
val close : t -> unit Lwt.t
val submit : t -> ('a -> 'b) -> 'a -> 'b Lwt.t

val log_error : (string -> unit) ref
val log_info : (string -> unit) ref
val string_of_exn : (exn -> string) ref

(*
module Full :
sig
  type ('central_request, 'central_response, 'worker_data) t

  val create :
    int ->
    ('central_request -> 'central_response Lwt.t) ->
    'worker_data ->
    ('central_request, 'central_response, 'worker_data) t

  val close : ('central_request, 'central_response, 'worker_data) t -> unit Lwt.t

  val submit :
    ('central_request, 'central_response, 'worker_data) t ->
    (('central_request -> 'central_response) ->
       'worker_data ->
       'worker_request -> 'worker_response) ->
    ('worker_response -> unit) ->
    'worker_request -> unit
end
*)
