#! /usr/bin/perl 
# (c) 1996 Heiko Schlittermann <heiko@lotte.sax.de>
# Usage:
# 	* Go into the directory of your packages to be uploaded.
#	* Simply say `upload --to chiark' and all will be done
#	
#	* Destination is the host named or a default host.
#	* The .changes files is read and the mentioned files
#	  are uploaded, _after_ checking their md5sums.
#	* The upload is logged in *.upload.
#	* Mail is sent upon completion.
#	* Files already uploaded to a host are not uploaded 
#	  again.
#	* configuration is read from
#	  	- xCONFDIRx/dupload.conf
#		- ~/.dupload
#		- ./dupload.conf


BEGIN { 
	$ENV{PERL_INC} # for my tests only
		and unshift @INC, $ENV{PERL_INC};
	unshift @INC, "xPKGLIBDIRx"; 
}

#use strict;
use Cwd;
use Carp;
use Getopt::Long;
use File::Basename;
require 'dupload-ftp.pl';	# NOTE: @INC is modified!!

# more ore less configurable constants
my $version = "xVERSIONx";
my $progname = basename($0);
my $user = getlogin() || $ENV{LOGNAME} || $ENV{USER};
my $myhost = `hostname --fqdn`; chomp $myhost;
my $cwd = cwd();

my $debug = 1;	# for somewhat more verbose output from the ftp module
my $force = 0;	# do it, even when already done
my $keep = 0;   # keep going, even if checksum errors
my $quiet = 0;	# don't talk too much

my $host = undef;				# target host
my $method = "ftp";				# transfer method
my $login = "anonymous";		# default login
my $passwd = "$user\@$myhost";	# ...

my $sendmail = "/usr/sbin/sendmail";

# global Variables
my (@changes,	# the files we'll have to read from
	@skipped,	# the packages we skipped
    $dry,		# if do-nothing
    $fqdn, 					# per host 
	$incoming, $queuedir,   # ...
	$mailto, $mailtx, $cc,  # ...
	$visiblename, $visibledomain,
	$fullname,
	%files, %package, %version, %arch,	# per job
	%dir, %changes, %log, %announce,    # ...
	%extra);

### Prototypes
sub configure(@);	# reads the config file(s)
sub ftp_open($$$);	# establishs the ftp connection
sub info($);		# print the available info (for a given host)
sub fatal(@);		# bail out
sub getpass();		# read password
sub w(@);			# warn (to STDERR if quiet, to STDOUT else)
sub p(@);			# print (suppress if quiet, to STDOUT else)

# some tests on constants
$user or fatal("Who am I? (can't get user identity\n");
$myhost or fatal("Who am I? (can't get hostname)\n");
$cwd or fatal("Where am I? (can't get current directory\n");
-x $sendmail or fatal("Probably wrong perms on `$sendmail': $!\n");

### Main
configure(
	"xCONFDIRx/dupload.conf",
	$ENV{HOME} && "$ENV{HOME}/.dupload.conf",
	"./dupload.conf");

$Getopt::Long::ignorecase = 0;
GetOptions qw(
	debug:i 
	force keep no 
	to=s print 
	quiet Version
) or fatal("Bad Options\n");

$dry = defined($::opt_no);
$debug = $::opt_debug || $debug;
$keep = $::opt_keep || $keep;
$host = $::opt_to;
$force = $::opt_force || $force;

# only info or version?
info($host), exit 0 if $::opt_print;
p("$progname Version: $version\n"), exit 0 if $::opt_Version;

# get the configuration for that host
# global, job independend information

$host or fatal("Need host to upload to.  (See --to option)\n\n");
{ my $nick = $config::cfg{$host};
  $method = $nick->{method} || $method;
  $fqdn = $nick->{fqdn} or fatal("Nothing known about host $host\n");
  $incoming = $nick->{incoming} or fatal("No Incoming dir\n");
  $queuedir = $nick->{queuedir};
  $mailto = $nick->{mailto};
  $mailtx = $nick->{mailtx} || $nick->{mailto};
  $cc = $nick->{cc};
  $login = $nick->{login} || $login if $method eq "ftp";
  $login = $nick->{login} || $user if $method eq "scp";
  $visibleuser = $nick->{visibleuser} || $user; chomp($visibleuser);
  $visiblename = $nick->{visiblename} || ''; chomp($visiblename);
  $fullname = $nick->{fullname} || '';
  undef $passwd unless $login =~ /^anonymous|ftp$/;
}

($mailto || $mailtx) or w("no announcement will be sent!\n");

# get the changes file names
@ARGV or push @ARGV, ".";	# use currend dir if no args
foreach (@ARGV) {
	my @f = undef;
	-r $_ or fatal("Can't read $_: $!\n");
	-f _ and do {
		/\.changes$/ or w("no .changes extension: $_\n");
		unshift(@changes, $_); 
		next;
	};
	-d _ and do {
		@f = <$_/*.changes> or w("no changes file in dir $_\n"); 
		unshift @changes, @f;
		next;
	};
}

@changes or die("No changes file, so nothing to do.\n");

p("Uploading ($method) to $fqdn:$incoming");
p("and moving to $fqdn:$queuedir") if $queuedir;
p("\n");

if ($method eq "ftp") {
	ftp::debug($debug);
	$ftp::hashnl = 0;
	$ftp::showfd = *STDOUT;
};

select((select(STDOUT), $| = 1)[0]);

# parse the changes files and update some 
# hashs, indexed by the jobname: 
#  %job - the files to be uploaded
#  %log - the logfile name
#  %dir - where the files are located
#  %announce -

PACKAGE: foreach (@changes) {
	my $dir = dirname($_);
	my $cf = basename($_);
	my $job = basename($cf, ".changes");
	my ($package, $version, $arch) = (split("_", $job, 3));
	my ($upstream, $debian) = (split("-", $version, 2));
	my $log = "$job.upload";

	my %md5;
	my (@files, @done, @extra);
	my (%mailto, %fields);

	chdir $dir or fatal("Can't chdir to $dir: $!\n");

	$dir{$job} = $dir;
	$changes{$job} = $cf;
	$package{$job} = $package;
	$version{$job} = $version;

	p "[ job $job from $cf";

	# scan the log file (iff any) for 
	# the files we've already put to the host
	# and the announcements already done
	if (-f $log) {
		open(L, "<$log") or fatal("Can't read $log: $!\n");
		while (<L>) {
			chomp;
			if (/^. /) { 
				/^u .*\s${host}\s/ and push(@done, $_),  next;
				/^a / and push(@done, $_), next;
			} else { /\s${host}\s/ and push @done, "u $_"; }
			next;
		}
		close(L);
	}

	# scan the changes file for architecture,
	# distribution code and the files
	# avoid duplicate mail addressees
	open(C, "<$cf") or fatal("Can't read $cf: $!\n");
	while (<C>) { 
		chomp;
		/^changes:\s+/i and $fields{changes}++;
		/^architecture:\s+/i and chomp($arch{$job} = $'), next;
		/^distribution:\s+/i and do { $_ = " $'";
			/\Wstable/i and $mailto{$mailto}++;
			/\Wcontrib/i and $mailto{$mailto}++;
			/\Wnon-free/i and $mailto{$mailto}++;
			/\Wunstable/i and $mailto{$mailtx}++;
			/\Wexperimental/i and $mailto{$mailtx}++;
			next;
		};
		/^files:\s/i and last; 
	}
	foreach (keys %mailto) {
		my $k = $_;
		p "\n  announce ($cf) to $k";
		if (grep(/^a .*\s${k}\s/, @done)) { p " already done"; }
		else { 
			$announce{$job} = join(" ", $announce{$job}, $_);
			p " will be sent";
		}
	}

	# search for extra announcement files
	foreach ("${package}", 
			"${package}_${upstream}",
			"${package}_${upstream}-${debian}") {
		$_ .= ".announce";
		-r $_ and push @extra, $_;
	}
	if (@extra) {
		p ", as well as\n  ", join(", ", @extra);
		$extra{$job} = [@extra];
	}

	# read the files from the changes file
	while (<C>) {
		chomp;
		/^ / and do { 
			my ($md5, $size, $sect, $pri, $file) = split; 
			$md5{$file} = $md5;
		}
	}
	close(C);
	%md5 && $fields{changes} or p(": not a changes file ]\n"), next PACKAGE;

	# test the md5sums
	foreach (keys %md5) {
			my $file = $_;
			p "\n $file";
			if (-r $file) { $_ = `md5sum $file`; $_ = (split)[0]; }
			else { print ": $!"; $_ = ""; }
			$md5{$file} eq $_ or do {
				$keep or fatal("MD5sum mismatch for $file\n");
				w("MD5sum mismatch for $file",
					", skipping $job\n");
				push @skipped, $cf;
				next PACKAGE;
			};
			p ", md5sum ok";
			if (!$force && @done && grep(/^u ${file}/, @done)) {
				p ", already done for $host";
			} else {
				push @files, $file;
			}
			next; 
	};

	# The changes file itself
	p "\n $cf ok";
	if (!$force && @done && grep(/^u ${cf}/, @done)) {
		p ", already done for $host";
	} else { push @files, $cf; }

	if (@files) {
		$log{$job} = $log;
		$files{$job} = [ @files ];
	}
	p " ]\n";
} continue {
	chdir $cwd or fatal("Can't chdir back to $cwd\n");
}

chdir $cwd or fatal("Can't chdir to $cwd: $!\n");

@skipped and w("skipped: @skipped\n");
%files or p("Nothing to upload\n"), exit 0;

if ($method eq "ftp") {
	$passwd = getpass() unless defined $passwd;
	p "Uploading (ftp) to $host ($fqdn)\n";
	if (!$dry) {
		ftp_open($fqdn, $login, $passwd);
		ftp::cwd($incoming);
	} else {
		p "+ ftp_open($fqdn, $login, $passwd)\n";
		p "+ ftp::cwd($incoming\n";
	}
} elsif ($method eq "scp") {
	p "Uploading (scp) to $host ($fqdn)\n";
} else {
	fatal("Unknown upload method\n");
}


JOB: foreach (keys %files) {
	my $job = $_;
	my @files = @{$files{$job}};

	chdir $cwd or fatal("Can't chdir to $cwd: $!\n");
	chdir $dir{$job} or fatal("Can't chdir to $dir{$job}: $!\n");

	p "[ Uploading job $job";
	@files or p ("\n nothing to do ]"), next;


	foreach (@files) {
		my $file = $_;
		my $size = -s;
		my $t;

		p(sprintf "\n $file %0.1f kB ", $size / 1000);
		$t = time();
		if ($method eq "ftp") {
			if (!$dry) {
				ftp::put($file, $file) or ftp::delete($file) 
					or fatal("Can't upload $file\n");
				$t = time() - $t;
			} else {
				p "\n+ ftp::put($file)";
				$t = 1;
			}
		} elsif ($method eq "scp") {
			if (!$dry) {
				system("scp $file $login\@$fqdn:$incoming");
				fatal("scp $file failed\n") if $?;
				$t = time() - $t;
				system("ssh -l $login $fqdn chmod 0644 $incoming/$file");
				fatal("ssh ... chmod 0644 failed\n") if $?;
			} else {
				p "\n+ scp $file $login\@$fqdn:$incoming";
				p "ssh -l $login $fqdn chmod 0644 $incoming/$file";
				$t = 1;
			}
		}

		if ($queuedir) {
			p", renaming";
			if ($method eq "ftp") {
				if (!$dry) {
					ftp::rename($file, $queuedir . $file) 
						or ftp::delete($file)
						or fatal("Can't rename $file -> $queuedir$file\n");
				} else {
					p "\n+ ftp::rename($file, $queuedir$file)";
				}
			} elsif ($method eq "scp") {
				if (!$dry) {
					system("ssh -l $login $fqdn \"mv $incoming$file $queuedir$file\"");
					fatal("ssh -l $login $fqdn: mv failed\n") if $?;
				} else {
					p "\n+ ssh -l $login $fqdn \"mv $incoming$file $queuedir$file\"";
				}
			}
		}

		p ", ok";
		p (sprintf " (${t} s, %.2f kB/s)", $size / 1000 / ($t || 1));

		if (!$dry) {
			open(L, ">>$log{$job}") or w "Can't open $log{$file}: $!\n";
			print L "u $file $host " . localtime() . "\n";
			close(L);
		} else {
			p "\n+ log to $log{$job}\n";
		}
	}

	if ($announce{$job}) {
		p "\n announcing to $announce{$job}";
		if (!$dry) {
			open(M, "|$sendmail -f $visibleuser"
					. ($visiblename  ? "\@$visiblename" : "") 
					. ($fullname  ? " -F '($fullname)'" : "")
					. " $announce{$job}")
				or fatal("Can't pipe to $sendmail $!\n");
		} else {
			p "\n+ announce to $announce{$job}\n";
			open(M, ">&STDOUT");
		}

		print M <<xxx;
X-dupload: $version
xxx
		$cc and print M <<xxx;
Cc: $cc
xxx
		print M <<xxx;
Subject: Uploaded $package{$job} $version{$job} ($arch{$job}) to $host

xxx
		foreach (@{$extra{$job}}) {
			my $line;
			open (A, "<$_") 
				or w("Can't open extra announce $_: $!\n"), next;
			p " ($_";
			while ($line = <A>) { print M  $line; }
			close(A);
			p(" ok)");
		}

		open(C, "<$changes{$job}") 
			or fatal("Can't open $changes{$job} $!\n");
		while (<C>) { print M; }
		close(C);

		close(M);
		if ($?) { p ", failed"; }
		else { p ", ok"; }

		if (!$dry) {
			open(L, ">>$log{$job}") 
				or w("can't open logfile $log{$job}: $!\n");
			print L "a $changes{$job} $announce{$job} " . localtime() . "\n";
			close(L);
		} else {
			p "\n+ log announcemnt\n";
		}
	}
	p " ]\n";
}

if (!$dry) { ftp'close(); }
else { p "\n+ ftp::close\n"; }

@skipped and w("skipped: @skipped\n");

exit 0;

### SUBS
### open the connection
sub ftp_open($$$) {
	my ($remote, $user, $pass) = @_;
	my ($ftp_port, $retry_call, $attempts) = (21, 1, 1);

	$ftp::use_pasv = $user =~ /@/;

	&ftp::open($remote, $ftp_port, $retry_call, $attempts) == 1
		or fatal("Can't open ftp connection\n");
	$_ = &ftp::login($user, $pass)
		or fatal("Login as $user failed\n");
	&ftp::type('I')
		or fatal("Can't set binary type\n");
}

### Display what whe know ...
sub info($) {
	my ($host) = @_;

	foreach ($host || keys %config::cfg) {
		my $r = $config::cfg{$_};
		print <<xxx;
nick name: $_
real name: $r->{fqdn}
login    : $r->{login}
incoming : $r->{incoming}
queuedir : $r->{queuedir}
mail to  : $r->{mailto}
mail to x: $r->{mailtx}
cc       : $r->{cc}

xxx
	}
}

### Read the configuration
sub configure(@) {
	my @conffiles = @_;
	foreach (@conffiles) { 
		-r or splice(@conffiles, $_, 1), next; 
		do $_ or fatal("$@\n");
	}
	@conffiles or fatal("No configuration files\n");
}

### Die
sub fatal(@) {
	w();
	croak("$progname: @_");
}

### password
sub getpass() {
	system "stty -echo cbreak </dev/tty"; $? and fatal("stty");
	print "\aPassword for ${login}'s ftp account on $fqdn: ";
	chomp($_ = <STDIN>);
	print "\n";
	system "stty echo -cbreak </dev/tty"; $? and fatal("stty");
	return $_;
};

###
# output
# p() prints to STDOUT if !$quiet
# w()          ....             ,
#     but to STDERR if !quiet
											{
my $nl;
sub p(@) {
	$nl = $_[$#_] =~ /\n$/;
	print STDOUT @_ if !$quiet;
}

sub w(@) {
	if ($quiet) { print STDERR "warning: ", @_; }
	else { 
		unshift @_, "warning: ";
		unshift @_, "\n" if !$nl;
		print STDOUT @_;
	}
	$nl = $_[$#_] =~ /\n$/;
}
											} 

# ex:set ts=4 sw=4:
