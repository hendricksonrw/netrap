#!/usr/bin/perl

BEGIN {
    unshift @INC, ".";
};

use strict;

use Data::Dumper;

use EventDispatch;

use IO::File;
use Netrap::Socket::File;
use Netrap::FlowManager;
use Netrap::Socket::HTTPListen;

# # my $f = new IO::File("< x.txt");
# my $fs = new Netrap::Socket::File("x.txt");
#
# # my $y = new IO::File("< y.txt");
# my $ys = new Netrap::Socket::File('y.txt');
#
# # my $o = new IO::File("> -") or die $!;
# my $os = new Netrap::Socket::File("-");
#
# my $fm = new Netrap::FlowManager([$fs, $ys], [$os]);


my $hl = new Netrap::Socket::HTTPListen(2560);
# $fm->addSink($os);
# $fm->addFeeder($s);

while (Netrap::Socket::Select()) {
#     if ((keys %{$fm->{feeders}}) == 0 && $os->canwrite()) {
#         printf "All finished\n";
#         exit 0;
#     }
}
