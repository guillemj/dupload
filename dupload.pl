#! /usr/bin/perl 
# (c) 1996 Heiko Schlittermann <heiko@lotte.sax.de>
# (c) 1999 Stephane Bortzmeyer <bortzmeyer@debian.org>
# Usage:
# 	* Go into the directory of your packages to be uploaded.
#	* Simply say `dupload --to chiark' and all will be done
#	
#	* Destination is the host named or a default host.
#	* The .changes files is read and the mentioned files
#	  are uploaded, _after_ checking their md5sums.
#	* The upload is logged in *.upload.
#	* Mail is sent upon completion.
#	* Files already uploaded to a host are not uploaded 
#	  again.
#	* configuration is read from
#	  	- /etc/dupload.conf
#		- ~/.dupload.conf
#		- ./dupload.conf


#BEGIN { 
#	$ENV{PERL_INC} # for my tests only
#		and unshift @INC, $ENV{PERL_INC};
#	unshift @INC, ""; 
#}

use strict;
use 5.003; # Because of the prototypes
use Cwd;
use Getopt::Long;
use File::Basename;
use Net::FTP;
use English;

# more or less configurable constants
my $version = "2.4";
my $progname = basename($0);
my $user = getlogin() || $ENV{LOGNAME} || $ENV{USER};
my $myhost = `hostname --fqdn`; chomp $myhost;
my $cwd = cwd();

my $debug = 0;	# for somewhat more verbose output from the ftp module
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
    @all_the_files,     # ... we installed (for postupload processing)
    @all_the_debs,      # ... we installed (for postupload processing)
    %all_packages,      # All Debian binary packages we installed 
                        # (for postupload processing)
    $scpfiles,
    $dry,		# if do-nothing
    $mailonly,          
    $fqdn, 					# per host 
    $server,
    $dinstall_runs, $passive,
    $nomail, $archive, $noarchive,
    %preupload, %postupload,
    $result,
    $new_dpkg_dev,
    $incoming, $queuedir,   # ...
    $mailto, $mailtx, $cc,  # ...
    $visiblename, $visibleuser, $visibledomain,
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
sub announce_if_necessary($);
sub run ($$);           # Runs an external program and return its exit status

# some tests on constants
$user or fatal("Who am I? (can't get user identity)\n");
$myhost or fatal("Who am I? (can't get hostname)\n");
$cwd or fatal("Where am I? (can't get current directory)\n");
-x $sendmail or fatal("Probably wrong perms on `$sendmail': $!\n");

### Main
configure(
	"/etc/dupload.conf",
	$ENV{HOME} && "$ENV{HOME}/.dupload.conf",
	"./dupload.conf");

$Getopt::Long::ignorecase = 0;
GetOptions qw(
	debug:i 
        help
	force keep no nomail noarchive
        mailonly
	to=s print 
       quiet Version version
) or fatal("Bad Options\n");

$dry = defined($::opt_no);
$mailonly = defined($::opt_mailonly);
if ($mailonly) {
    $dry = 1;
}
$debug = $::opt_debug || $debug;
$keep = $::opt_keep || $keep;
$host = $::opt_to || $config::default_host;
$force = $::opt_force || $force;
$nomail = $::opt_nomail || 0;
$quiet = $::opt_quiet;
# "new" is for 'potato'.
$new_dpkg_dev = 0;
 
# only info or version?
info($host), exit 0 if $::opt_print;
p("$progname Version: $version\n"), exit 0 if 
    ($::opt_Version or $::opt_version);

if ($::opt_help) {
    p ("Usage: $progname --to HOST FILE.changes ...\n" .
       "\tUploads the files listed in the above '.changes' to the\n".
       "\thost HOST.\n" .
       "\tSee dupload(1) for details.\n");
    exit 0;
}

# get the configuration for that host
# global, job independend information

$host or fatal("Need host to upload to.  (See --to option or the default_host configuration variable)\n");
{ my $nick = $config::cfg{$host};
  $method = $nick->{method} || $method;
  $fqdn = $nick->{fqdn} or fatal("Nothing known about host $host\n");
  $incoming = $nick->{incoming} or fatal("No Incoming dir\n");
  $queuedir = $nick->{queuedir};
  $mailto = $nick->{mailto};
  $mailtx = $nick->{mailtx} || $nick->{mailto};
  $cc = $nick->{cc};
  $dinstall_runs = $nick->{dinstall_runs};
  $passive = $nick->{passive}; 
  if ($passive and ($method ne "ftp")) { 
      fatal ("Passive mode is only for FTP ($host)");
  }
  if (defined ($nick->{archive})) {
      $archive = $nick->{archive};
  } 
  else {
      $archive = 1;
  }
  foreach my $category (qw/changes sourcepackage package file deb/) {
      if (defined ($nick->{preupload}{$category})) {
	  $preupload{$category} = $nick->{preupload}{$category};
      }
      else {
	  $preupload{$category} = $config::preupload{$category};
      }
      if (defined ($nick->{postupload}{$category})) {
      	  $postupload{$category} = $nick->{postupload}{$category};
      }
      else {
      	  $postupload{$category} = $config::postupload{$category};
      }
  }
  
  $login = $nick->{login} || $login if $method eq "ftp";
  $login = $nick->{login} || $user if ($method eq "scp" || $method eq "scpb");
  $visibleuser = $nick->{visibleuser} || $user; chomp($visibleuser);
  $visiblename = $nick->{visiblename} || ''; chomp($visiblename);
  $fullname = $nick->{fullname} || '';
  undef $passwd unless $login =~ /^anonymous|ftp$/;
  if ($nick->{password} && ($login =~ /^anonymous|ftp$/)) { 
      # Do not accept passwords in configuration file,
      # except for anonymous logins.
      $passwd = $nick->{password};
  }
}

# Command-line options have precedence over configuration files:

$noarchive = $::opt_noarchive || (! $archive);

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

# preupload code for changes files
foreach my $change (@changes) {
    if ($preupload{'changes'}) {
        my ($result) = run $preupload{'changes'}, [$change];
        if (! $result) {
            fatal "Pre-upload \'$preupload{'changes'}\' failed for $change\n  ";
        }
    }
}

p("Uploading ($method) to $fqdn:$incoming");
p("and moving to $fqdn:$queuedir") if $queuedir;
p("\n");

select((select(STDOUT), $| = 1)[0]);

# parse the changes files and update some 
# hashs, indexed by the jobname: 
#  %job - the files to be uploaded
#  %log - the logfile name
#  %dir - where the files are located
#  %announce -

PACKAGE: foreach my $change (@changes) {
	my $dir = dirname($change);
	my $cf = basename($change);
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

        # preupload code for source package
	if ($preupload{'sourcepackage'}) {
	    my ($result) = run $preupload{'sourcepackage'}, 
	                       [basename($package) . " $version"];
	    if (! $result) {
		fatal "Pre-upload \'$preupload{'sourcepackage'}\' " .
		    "failed for " . basename($package) . " $version\n  ";
	    }
	}

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
                /^format: (\d)\.(\d+)/i and do {
                       my ($major, $minor) = ($1, $2);
                       if (($major == 1 && $minor >= 6) or ($major >= 2)) {
			   if ($dinstall_runs) {
                               $nomail = 1;
			   }
			   $new_dpkg_dev = 1;
                       }
                };
		/^distribution:\s+/i and do { $_ = " $'";
			/\Wstable/i and $mailto{$mailto}++;
			/\Wunstable/i and $mailto{$mailtx}++;
                        /\Wfrozen/i and $mailto{$mailtx}++;
			/\Wexperimental/i and $mailto{$mailtx}++;
			next;
		};
		/^files:\s/i and last; 
	}
	foreach (keys %mailto) {
		my $k = $_;  
                if (! $nomail) {
		    p "\n  announce ($cf) to $k";
		    if (grep(/^a .*\s${k}\s/, @done)) { p " already done"; }
                    else { 
                       $announce{$job} = join(" ", $announce{$job}, $_);
                       p " will be sent";
		   }
                }
                elsif ( $new_dpkg_dev ) {
                       p " New dpkg-dev, announcement will NOT be sent";      
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
			if (!$force && @done && grep(/^u \Q${file}\E/, @done)) {
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
       	} else {
	    $log{$job} = $log;
	    announce_if_necessary($job);
	    if (!$dry) {
		open(L, ">>$log{$job}") 
		    or w("can't open logfile $log{$job}: $!\n");
		print L "s $changes{$job} $host " . localtime() . "\n";
		close(L);
	    } else {
		p "\n+ log successful upload\n";
	    }
	}
	p " ]\n";

        # preupload code for all files and for '.deb' 
        foreach my $file (@files) {
	    push @all_the_files, $file;
	    if ($preupload{'file'}) {
		my ($result) = run $preupload{'file'}, [$file];
		if (! $result) {
		    fatal "Pre-upload \'$preupload{'file'}\' " .
			"failed for $file\n  ";
		}
	    }
	    if ($file =~ /\.deb$/) {
		push @all_the_debs, $file;
		my ($binary_package, $version, $garbage) = split ('_', $file);
       	        $binary_package = basename($binary_package);
	        $all_packages{$binary_package} = $version;
		if ($preupload{'package'}) {
		    my ($result) = run $preupload{'package'}, 
                                   [$binary_package, $version];
                    if (! $result) {
                          fatal "Pre-upload \'$preupload{'dpackage'}\' " .
                               "failed for $binary_package $version\n  ";
                }
            }
            if ($preupload{'deb'}) {
                            my ($result) = run $preupload{'deb'}, [$file];
                            if (! $result) {
                               fatal "Pre-upload \'$preupload{'deb'}\' " .
                               "failed for $file\n  ";
                            }
             }
        }
       }


} continue {
	chdir $cwd or fatal("Can't chdir back to $cwd\n");
}

chdir $cwd or fatal("Can't chdir to $cwd: $!\n");

@skipped and w("skipped: @skipped\n");
%files or (p("Nothing to upload\n"), exit(0));

if ($method eq "ftp") {
	if (!$dry) {
	    $passwd = getpass() unless defined $passwd;
	} else { 
		p "+ getpass()\n";
	}
	p "Uploading (ftp) to $host ($fqdn)\n";
	if (!$dry) {
		ftp_open($fqdn, $login, $passwd);
		$server->cwd($incoming);
	} else {
		p "+ ftp_open($fqdn, $login, $passwd)\n";
		p "+ ftp::cwd($incoming\n";
	}
} elsif ($method eq "scp" || $method eq "scpb") {
	p "Uploading (scp) to $host ($fqdn)\n";
} else {
	fatal("Unknown upload method\n");
}

JOB: foreach (keys %files) {
	my $job = $_;
	my @files = @{$files{$job}};
	my $mode;
	my ($bm, $allfiles);
	$scpfiles = "";

	chdir $cwd or fatal("Can't chdir to $cwd: $!\n");
	chdir $dir{$job} or fatal("Can't chdir to $dir{$job}: $!\n");

	p "[ Uploading job $job";
	@files or p ("\n nothing to do ]"), next;

	my $wrong_mode = 0; # For scpb only. A priori, the mode is right for every file
	foreach (@files) {
		my $file = $_;
		my $size = -s;
		my $t;

		p(sprintf "\n $file %0.1f kB ", $size / 1024);
		$t = time();
		if ($method eq "ftp") {
			if (!$dry) {
			    unless ($server->put($file, $file)) {
                                        $result = $server->message();
                                        $server->delete($file) ;
					fatal("Can't upload $file: $result");
				}
				$t = time() - $t;
			} else {
				p "\n+ ftp::put($file)";
				$t = 1;
			}
		} elsif ($method eq "scp") {
                        $mode = (stat($file))[2];
			if (!$dry) {
				system("scp -p -q $file $login\@$fqdn:$incoming");
				fatal("scp $file failed\n") if $?;
				$t = time() - $t;
                                # Small optimization
                                if ($mode != 33188) { # rw-r--r-- aka 0644
				    system("ssh -x -l $login $fqdn chmod 0644 $incoming/$file");
				    fatal("ssh ... chmod 0644 failed\n") if $?;
                                }
			} else {
				p "\n+ scp -p -q $file $login\@$fqdn:$incoming";
                                if ($mode != 33188) { # rw-r--r-- aka 0644
                                     p "\n+ ssh -x -l $login $fqdn chmod 0644 $incoming/$file";
                                }
				$t = 1;
			}
                } elsif ($method eq "scpb") {
                	$scpfiles  .= "$file ";
			$mode = (stat($file))[2];
			# Small optimization
			if ($mode != 33188) { # rw-r--r-- aka 0644
			   $wrong_mode = 1;
			}
			$t = 1;
			$bm = 1;
		}

		if ($queuedir) {
			p", renaming";
			if ($method eq "ftp") {
				if (!$dry) {
					$server->rename($file, $queuedir . $file) 
						or 
                                                $result=$server->message(),
                                                $server->delete($file),
						fatal("Can't rename $file -> $queuedir$file\n");
				} else {
					p "\n+ ftp::rename($file, $queuedir$file)";
				}
			} elsif ($method eq "scp") {
				if (!$dry) {
					system("ssh -x -l $login $fqdn \"mv $incoming$file $queuedir$file\"");
					fatal("ssh -x -l $login $fqdn: mv failed\n") if $?;
				} else {
					p "\n+ ssh -x -l $login $fqdn \"mv $incoming$file $queuedir$file\"";
				}
			}
		}

		p ", ok";
		p (sprintf " (${t} s, %.2f kB/s)", $size / 1024 / ($t || 1));

		if (!$bm) {
			if (!$dry) {
				open(L, ">>$log{$job}") or w "Can't open $log{$job}: $!\n";
				print L "u $file $host " . localtime() . "\n";
				close(L);
			} else {
				p "\n+ log to $log{$job}\n";
			}
			$bm = 0;
		}
	}
	if ($method eq "scpb") {
        	my $cmd = "ssh -x -l $login $fqdn 'cd $incoming;chmod 0644 $scpfiles;".
 			($queuedir ? "mv $scpfiles $queuedir" : "").
			"'";
               if (!$dry) {
                       p "\n";
                       system("scp $scpfiles $login\@$fqdn:$incoming");
                       fatal("scp $scpfiles failed\n") if $?;
		       if ($wrong_mode) {
			   system($cmd);
                       }
                       fatal("$cmd failed\n") if $?;
               } else {
                       p "\n+ scp $scpfiles $login\@$fqdn:$incoming";
                       p "\n+ $cmd";
                }
		$allfiles = $scpfiles;
        }

	if ($bm) {
		if (!$dry) {
			open(L, ">>$log{$job}") or w "Can't open $log{$job}: $!\n";
			foreach (split(/ /, $allfiles)) {
				print L "u $_ $host " . localtime() . "\n";
			}
			close(L);
		} else {
			p "\n+ log to $log{$job}\n";
		}
	}

        announce_if_necessary($job);
        if (!$dry) {
            open(L, ">>$log{$job}") 
                or w("can't open logfile $log{$job}: $!\n");
            print L "s $changes{$job} $host " . localtime() . "\n";
            close(L);
        } else {
            p "\n+ log successful upload\n";
        }
	p " ]\n";

}

if ($method eq "ftp") {
  if (!$dry) { $server->close(); }
  else { p "\n+ ftp::close\n"; }
}

# postupload code for changes files
if (! $dry) {
    foreach my $change (@changes) {
	if ($postupload{'changes'}) {
	    my ($result) = run $postupload{'changes'}, [$change];
	    if (! $result) {
		fatal "Post-upload \'$postupload{'changes'}\' " . 
		    "failed for $change\n  ";
	    }
	}
	my ($package, $version, $arch) = (split("_", $_, 3));
	if ($postupload{'sourcepackage'}) {
	    my ($result) = run $postupload{'sourcepackage'}, 
	                       [basename($package), $version];
	    if (! $result) {
		fatal "Post-upload \'$postupload{'sourcepackage'}\' " . 
		    "failed for " . basename($package) . " $version\n  ";
	    }
	}
    }
    foreach my $file (@all_the_files) {	
	if ($postupload{'file'}) {
	    my ($result) = run $postupload{'file'}, [$file];
	    if (! $result) {
		fatal "Post-upload \'$postupload{'file'}\' " . 
		    "failed for $file\n  ";
	    }
	}
    }
    foreach my $file (@all_the_debs) {	
	if ($postupload{'deb'}) {
	    my ($result) = run $postupload{'deb'}, [$file];
	    if (! $result) {
		fatal "Post-upload \'$postupload{'deb'}\' " . 
		    "failed for $file\n  ";
	    }
	}
    }
    foreach my $package (keys (%all_packages)) {	
	if ($postupload{'package'}) {
	    my ($result) = run $postupload{'package'}, 
                               [$package, $all_packages{$package}];
	    if (! $result) {
		fatal "Post-upload \'$postupload{'package'}\' " . 
		    "failed for $package $all_packages{$package}\n  ";
	    }
	}
    }
}

@skipped and w("skipped: @skipped\n");

exit 0;

### SUBS

###
sub announce_if_necessary ($) {
    my ($job) = @_[0];
    my ($opt_fullname) = " -F '($fullname)'";
    my ($msg);
    if ($announce{$job} and (! $nomail)) {
	if ($config::no_parentheses_to_fullname) {
	       $opt_fullname = " -F '$fullname'";
	}
	$fullname =~ s/\'/''/;
	my $sendmail_cmd = "|$sendmail -f $visibleuser"
	    . ($visiblename  ? "\@$visiblename" : "") 
		. ($fullname  ? $opt_fullname : "")
		    . " $announce{$job}";
	$msg = "announcing to $announce{$job}";
	if ($cc) {
	    $sendmail_cmd .= " " . $cc;
	    $msg .= " and $cc";
	}
	p $msg . "\n";
	if ((!$dry) or ($mailonly)) {
	    open(M, $sendmail_cmd) or fatal("Can't pipe to $sendmail $!\n");
	} else {
	    p "\n+ announce to $announce{$job} using command ``$sendmail_cmd''\n";
	    open(M, ">&STDOUT");
	}
	
	print M <<xxx;
X-dupload: $version
To: $announce{$job}
xxx
        $cc and print M <<xxx;
Cc: $cc
xxx
        $noarchive and print M <<xxx;
X-No-Archive: yes
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
	    p "\n+ log announcement\n";
	}
    }
}

### open the connection
sub ftp_open($$$) {
	my ($remote, $user, $pass) = @_;
	my ($ftp_port, $retry_call, $attempts) = (21, 1, 1);
	my ($request_passive) = 0;
	
	if (($user =~ /@/) or ($passive)) {
	    $request_passive = 1;
	    p "+ FTP passive mode selected\n";
	}
	
	# It may seems complicated, but it is to be sure that the
	# environment variable FTP_PASSIVE works (which needs no
        # Passive argument).
	if ($request_passive) {
	    $server = Net::FTP->new ("$fqdn", Passive => $request_passive);
	}
	else {
	    $server = Net::FTP->new ("$fqdn");
	}
	if (! $server) {
	    fatal ($@);
	}
	$server->debug($debug);

	$_ = $server->login($user, $pass)
		or die("Login as $user failed\n");
	$server->type('I')
		or fatal("Can't set binary type\n");
}

### Display what whe know ...
sub info($) {
	my ($host) = @_;

	foreach ($host || keys %config::cfg) {
		my $r = $config::cfg{$_};
		print <<xxx;
nick name     : $_
real name     : $r->{fqdn}
login         : $r->{login}
incoming      : $r->{incoming}
queuedir      : $r->{queuedir}
mail to       : $r->{mailto}
mail to x     : $r->{mailtx}
cc            : $r->{cc}
passive FTP   : $r->{passive}
dinstall runs : $r->{dinstall_runs}
archive mail  : $r->{archive}

xxx
	}
}

### Read the configuration
sub configure(@) {
	my @conffiles = @_;
	my @read = ();
	foreach (@conffiles) { 
		-r or next; 
		do $_ or fatal("$@\n");
		push @read, $_;
	}
	@read or fatal("No configuration files\n");
}

### password
sub getpass() {
	system "stty -echo cbreak </dev/tty"; $? and fatal("stty");
	print "\a${login}\@${fqdn}'s ftp account password: ";
	chomp($_ = <STDIN>);
	print "\n";
	system "stty echo -cbreak </dev/tty"; $? and fatal("stty");
	return $_;
};

###
# output
# p() prints to STDOUT if !$quiet
# w()          ....             ,
#     but to STDERR if $quiet
# fatal() dies
											{
my $nl;
sub p(@) { 
        return if $quiet;
	$nl = $_[$#_] =~ /\n$/;
	print STDOUT @_;
}

sub w(@) {
    if ($quiet) { print STDERR "$progname warning: ", @_; }
    else {
	$nl = $_[$#_] =~ /\n$/;
	unshift @_, "$progname warning: "; 
	unshift @_, "\n" if !$nl;
	print STDOUT @_;
    }
}

sub fatal(@) {
    my ($pack,$file,$line);
    ($pack,$file,$line) = caller();
    (my $msg = "$progname fatal error: @_ at $file line $line\n") =~ tr/\0//d;
    die $msg;
}

sub run ($$) {
    my ($command, $args) = @_;
    my (@args) = @{$args};
    my ($result);
    my ($i);
    foreach $i (0..$#args) {
	$args[$i] =~ s#/#\\/#g;
	my ($mycode) = "\$command =~ s/\%" . ($i+1) . "/$args[$i]/g;";
	# Substitute %1 by the first argument, etc
        $result = eval ($mycode);
	if (! defined ($result)) {
	    fatal ("Cannot eval arguments substitution $mycode: $@");
	}
    }
    system "$command";
    $result = $CHILD_ERROR>>8;
    return (! $result);
}

} 


# ex:set ts=4 sw=4:
