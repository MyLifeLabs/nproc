Nproc: Process pool implementation for OCaml
============================================

A master process creates a pool of N processes. Tasks can be submitted
asynchronously as a function `f` and its argument `x`. As soon as one of
the processes is available, it computes `f x` and returns the result.

This library allows to take advantage of multicore architectures
by message-passing and without blocking. Its implementation relies
on fork, pipes, Marshal and [Lwt](http://ocsigen.org/lwt/manual/).

Implementation status:
----------------------
- interface may still be subject to slight changes;
- passed a few units tests;
- used stream interface successfully at full scale.

Performance status:
-------------------
- observed 5x speedup on 8 cores when converting a stream of lines
  from one file to another.
  A task consisted in parsing a line, converting the record,
  doing one in-RAM database lookup per record, and printing the new record.
  Throughput was 50K records per second, using a granularity of 100
  records per task.


Do not hesitate to submit experience reports, either good or bad,
and interface suggestions before it is too late.
