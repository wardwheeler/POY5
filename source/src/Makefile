# $Id: Makefile 1929 2007-06-26 23:34:34Z andres $

# Instructions:
# You can compile a debug bytecode app by specifying DEBUG=-g
# You can compile a profiled bytecode app by specifying
#      OCAMLC=ocamlcp DEBUG="-p a"
# You can compile a profiled native app by specifying PROFILE=-p

# Change whatever options (compilers, compiler options, and so on) in this file
# Cleanup spaces so that we recognize proper options

SHELL = /bin/sh


subdirs = @subdirs@
top_srcdir = .
srcdir = .
prefix = /usr/local
exec_prefix = ${prefix}
mandir = $(prefix)/man/man1

CC = gcc
CPPFLAGS = 
CFLAGS = $(CPPFLAGS) -I //usr/include/malloc -isysroot / -g -O2 
LDFLAGS = 
LIBS = -cclib "-lz -framework Accelerate -lz -isysroot / -lm "
INSTALL = install

USEPARALLEL := false
USE_LARGE_MESSAGES := false
USEWIN32 := false
USE_LONG_SEQUENCES := true
USE_LARGE_ALPHABETS := true
USEINTERFACE := flat
USEGRAPHICS := @USEGRAPHICS@
USESHAREDHD := false
USE_XSLT := false
USE_LIKELIHOOD := true
USE_VERIFY_COSTS := false
OCAML := ocaml
OCAMLC := ocamlc.opt
OCAMLOPT := ocamlopt.opt 
OCAMLDEP := ocamldep.opt -slash
OCAMLTOP := ocamlmktop
OCAMLLEX := ocamllex.opt
OCAMLYACC := ocamlyacc
OCAMLBUILD := ocamlbuild.native
EXTRAS := 
OFLAGS :=  
NATIVEDYNLINK := dynlink.cmxa

.PHONY: commands.pdf poy.native poy.byte poy.top clean distclean install doc all poy uninstall portal.native portal install_server docs install_docs install_doc

##################################
# Basic Compilation Entry Points
#

poy : poy.native 

poy.top: 
	$(OCAMLBUILD) $@

poy.byte: 
	$(OCAMLBUILD) $@

poy.native: 
	$(OCAMLBUILD) $@

all: poy.byte poy.top VERSION poy.native

##################################
# Documentation through OCamlbuild

commands.pdf:
	$(OCAMLBUILD) $@
	cp _build/commands.pdf ./commands.pdf

doc: 
	$(OCAMLBUILD) commands.pdf
	cp _build/commands.pdf ./commands.pdf

docs: doc

##################################
# Cleaning / Removing POY
#

install: poy.native
	test -d $(prefix) || mkdir $(prefix)
	test -d $(prefix)/bin || mkdir $(prefix)/bin
	cp _build/poy.native _build/poy
	$(INSTALL) -m 0755 _build/poy $(prefix)/bin

install_doc: doc
	$(INSTALL) -m 0644 _build/poy.1 $(mandir)


install_docs: install_doc

uninstall:
	rm -f $(prefix)/bin/poy
	rm -f $(mandir)/poy.1

clean:
	rm -f *.native *.byte *.top
	rm -rf _build
	$(OCAMLBUILD) -clean

distclean: clean
	rm -f buildNumber.ml compileFlags.ml config.h \
		config.log config.status _tags myocamlbuild.ml \
		poy.native poy.byte poy.d.byte poy.top
	rm -f Makefile


##################################
# Commands for the portal / server
#

portal.native: poy.native xml/swami.xml 
	$(OCAMLBUILD) portal.native

portal : portal.native

xml/swami.xml:
	$(OCAMLBUILD) makeVersion.native
	export RESULT="`makeVersion.native -text`"; sed "s/VERSION/$${RESULT}/g" ../xml/swami.xml.in > ../xml/swami.xml

install_portal: install portal.native
	$(INSTALL) _build/portal.native $(prefix)/bin/


##################################
# Commands for testing
#

poy_test.byte: 
	$(OCAMLBUILD) $@

poy_test.native:
	$(OCAMLBUILD) poy_test.native
	cp ./_build/poy_test.native ../test/poy_test.native

VERSION:
	$(OCAMLBUILD) makeVersion.native
	export RESULT="`makeVersion.native -text`"; echo "POY $${RESULT}" > VERSION
	$(OCAMLBUILD) poy.native

