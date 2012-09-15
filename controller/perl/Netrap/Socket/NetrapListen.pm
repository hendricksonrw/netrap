package Netrap::Socket::NetrapListen;

use strict;
use vars qw(@ISA);

use IO::Socket::INET;

use Netrap::Socket;

@ISA = qw(Netrap::Socket);

sub new {
    my $proto = shift;
    my $class = ref($proto) || $proto;

    my $port = shift;

    my $sock = new IO::Socket::INET(LocalAddr => '0.0.0.0', LocalPort => $port, Proto => 'tcp', Listen => 8, ReuseAddr => 1, Blocking => 0) or die $!;

    my $self = $class->SUPER::new($sock);

    bless $self, $class;

    return $self;
}

sub ReadSelectorCallback {
    my $self = shift;

    my $netrapsock = new Netrap::Socket::Netrap($self->{sock}->accept());
}