# Makefile for dupload
# Copyright (C) 1996 Heiko Schlittermann
# Copyright (C) 2002 Josip Rodin

version = $(shell LC_ALL=C dpkg-parsechangelog|grep '^Version'|sed 's/^.*:[ \t]*//')

MAN1 = dupload.1
MAN5 = dupload.conf.5
MAN = $(MAN1) $(MAN5)
EXTRA_FILES = gpg-check pgp-check

prefix = /usr/local
confdir = /etc
bindir = $(prefix)/bin
mandir = $(prefix)/share/man
man1dir = $(mandir)/man1
man5dir = $(mandir)/man5
extradir = $(prefix)/share/dupload

INSTALL = install
POD2MAN = pod2man

mkdirhier = $(INSTALL) -d
inst_script = $(INSTALL) -m 755
inst_lib = $(INSTALL) -m 644
inst_data = $(INSTALL) -m 644

all: dupload $(MAN)

install:	all
	$(mkdirhier) $(bindir) $(man1dir) $(man5dir) $(extradir)
	$(inst_script) dupload $(bindir)
	$(inst_data) $(MAN1) $(man1dir)
	$(inst_data) $(MAN5) $(man5dir)
	$(inst_script) $(EXTRA_FILES) $(extradir)
	@echo; echo "** You should install dupload.conf to $(confdir)"; echo

clean:
	rm -f core *.[0-9]pod.* *~ $(MAN)

.PHONY: dupload
dupload:
	perl -c $@
	perl -c dupload.conf

%:	%pod
	$(POD2MAN) \
	  --section=$(subst .,,$(suffix $@)) \
	  --name=$$(echo $(basename $@) | perl -pe '$$_=uc') \
	  --center="Debian Project" \
	  --date="`LC_ALL=C date '+%B %Y'`" \
	  --release="dupload $(version)" \
	    $< >,$@ && mv -f ,$@ $@; \
	  rm -f ,$@

.PHONY:	all install clean