type t
val create : int -> t * unit Lwt.t
val close : t -> unit Lwt.t
val submit : t -> f: ('a -> 'b) -> 'a -> 'b Lwt.t

val iter_stream :
  nproc: int ->
  f: ('a -> 'b) ->
  g: ('b -> unit) ->
  'a Stream.t -> unit

val log_error : (string -> unit) ref
val log_info : (string -> unit) ref
val string_of_exn : (exn -> string) ref


module Full :
sig
  type ('serv_request, 'serv_response, 'env) t

  val create :
    int ->
    ('serv_request -> 'serv_response Lwt.t) ->
    'env ->
    ('serv_request, 'serv_response, 'env) t * unit Lwt.t

  val close :
    ('serv_request, 'serv_response, 'env) t -> unit Lwt.t

  val submit :
    ('serv_request, 'serv_response, 'env) t ->
    f: (('serv_request -> 'serv_response) -> 'env -> 'a -> 'b) ->
    'a -> 'b Lwt.t

  val iter_stream :
    nproc: int ->
    serv: ('serv_request -> 'serv_response Lwt.t) ->
    env: 'env ->
    f: (('serv_request -> 'serv_response) -> 'env -> 'a -> 'b) ->
    g: ('b -> unit) ->
    'a Stream.t -> unit

end
