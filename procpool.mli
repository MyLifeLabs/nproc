type t
val create : int -> t Lwt.t
val close : t -> unit
val submit : t -> ('a -> 'b) -> ('b -> unit) -> 'a -> unit

module Full :
sig
  type ('central_request, 'central_response, 'worker_data) t

  val create :
    int ->
    ('central_request -> 'central_response Lwt.t) ->
    'worker_data ->
    ('central_request, 'central_response, 'worker_data) t

  val close : ('central_request, 'central_response, 'worker_data) t -> unit

  val submit :
    ('central_request, 'central_response, 'worker_data) t ->
    (('central_request -> 'central_response) ->
       'worker_data ->
       'worker_request -> 'worker_response) ->
    ('worker_response -> unit) ->
    'worker_request -> unit
end
