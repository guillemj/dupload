# Makefile for dupload
# (c) 1996 Heiko Schlittermann

PACKAGE = dupload
version = $(shell dpkg-parsechangelog|grep '^Version'|sed 's/^.*:[ \t]*//')

TARGET = dupload
LIBS = dupload-ftp.pl lchat.pl
CONFIG = dupload.conf
MAN1 = dupload.1 
MAN5 = dupload.5
MAN = $(MAN1) $(MAN5)

prefix = /usr/local
confdir = /etc
bindir = $(prefix)/bin
mandir = $(prefix)/man
man1dir = $(mandir)/man1
man5dir = $(mandir)/man5
libdir = $(prefix)/lib
pkglibdir = $(libdir)/$(PACKAGE)


INSTALL = install
POD2MAN = pod2man

mkdirhier = $(INSTALL) -d
inst_script = $(INSTALL)
inst_lib = $(INSTALL) -m644
inst_data = $(INSTALL) -m644

all:		$(TARGET) $(MAN)

install:	all
	$(mkdirhier) $(bindir) $(pkglibdir) $(man1dir) $(man5dir)
	$(inst_script) $(TARGET) $(bindir)
	$(inst_lib) $(LIBS) $(pkglibdir)
	$(inst_data) $(MAN1) $(man1dir)
	$(inst_data) $(MAN5) $(man5dir)
	@echo; echo "** You should install $(CONFIG) to $(confdir)"; echo

clean:
	-rm -f core *~ $(TARGET) $(MAN)
	

%:	%.pl
	sed -e 's,xPKGLIBDIRx,$(pkglibdir),g' \
	    -e 's,xCONFDIRx,$(confdir),g' \
	    -e "s,xVERSIONx,$(version),g" \
	<$^ >,$@\
	&& chmod +x ,$@\
	&& mv -f ,$@ $@;\
	rm -f ,$@

%:	%pod
	$(POD2MAN) \
		--section=`echo $@ | sed 's/^.*\.//'`\
		--center="Debian GNU/Linux manual"\
		--date="Debian Project"\
		--release="`date '+%B %Y'`" \
	$< >,$@ && mv -f ,$@ $@;\
	rm -f ,$@

.PHONY:	all install clean
