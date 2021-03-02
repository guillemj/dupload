# Makefile for dupload
# Copyright © 1996 Heiko Schlittermann
# Copyright © 2002 Josip Rodin
# Copyright © 2017, 2019-2020 Guillem Jover <guillem@debian.org>

PACKAGE = dupload
VERSION = $(shell dpkg-parsechangelog -SVersion)
RELTIME = $(shell dpkg-parsechangelog -STimestamp)
MANDATE = $(shell TZ=UTC0 LC_ALL=C date '+%F' --date="@$(RELTIME)")

MAN1 = dupload.1
MAN5 = dupload.conf.5
MAN = $(MAN1) $(MAN5)
EXTRA_FILES = \
  hooks/openpgp-check \
  hooks/debian-security-auth \
  hooks/debian-source-only \
  $(nil)

prefix = /usr
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

repl_script = sed -i \
	-e "s:^my \$$version = '.*';:my \$$version = '$(VERSION)';:" \
	$(nil)

all: $(MAN)

install:	all
	$(mkdirhier) $(DESTDIR)$(bindir)
	$(mkdirhier) $(DESTDIR)$(confdir)
	$(mkdirhier) $(DESTDIR)$(man1dir) $(DESTDIR)$(man5dir)
	$(mkdirhier) $(DESTDIR)$(extradir)
	$(inst_script) dupload $(DESTDIR)$(bindir)
	$(repl_script) $(DESTDIR)$(bindir)/dupload
	$(inst_data) $(MAN1) $(DESTDIR)$(man1dir)
	$(inst_data) $(MAN5) $(DESTDIR)$(man5dir)
	$(inst_script) $(EXTRA_FILES) $(DESTDIR)$(extradir)
	$(inst_data) dupload.conf $(DESTDIR)$(confdir)

clean:
	rm -f core *.[0-9].pod.* *~ $(MAN)

.PHONY: check

check:
	prove -Ilib

%:	%.pod
	$(POD2MAN) \
	  --section=$(subst .,,$(suffix $@)) \
	  --name=$(basename $@) \
	  --center="Debian Project" \
	  --date="$(MANDATE)" \
	  --release="$(VERSION)" \
	    $< >,$@ && mv -f ,$@ $@; \
	  rm -f ,$@

.PHONY:	all install clean

dist:
	git archive \
	    --prefix=$(PACKAGE)-$(VERSION)/ \
	    --output=$(PACKAGE)-$(VERSION).tar.xz \
	    $(VERSION)
