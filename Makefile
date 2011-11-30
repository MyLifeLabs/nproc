# This Makefile provides only what is needed to build and install nproc.
# Development is done with omake using the OMakefile.

.PHONY: default all opt install uninstall

default: all opt

META: META.in VERSION
	echo "version = \"$$(cat VERSION)\"" > META
	cat META.in >> META

all: META
	ocamlfind ocamlc -c nproc.mli -package lwt.unix
	ocamlfind ocamlc -a -g nproc.ml -o nproc.cma -package lwt.unix
opt: META
	ocamlfind ocamlc -c nproc.mli -package lwt.unix
	ocamlfind ocamlopt -a -g nproc.ml -o nproc.cmxa -package lwt.unix
install:
	ocamlfind install nproc META \
          `find nproc.mli nproc.cmi \
                nproc.cmo nproc.cma \
                nproc.cmx nproc.o nproc.cmxa nproc.a`
uninstall:
	ocamlfind remove nproc

.PHONY: clean
clean:
	omake clean
	rm -f *.omc
