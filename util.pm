package util;

use Carp;
use base Exporter;
@EXPORT = 'fatal';

### Die
sub fatal(@) {
	main::w();
	croak("$progname: @_");
}



1;
