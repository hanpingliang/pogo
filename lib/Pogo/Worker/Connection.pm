###########################################
package Pogo::Worker::Connection;
###########################################
use strict;
use warnings;
use Log::Log4perl qw(:easy);
use AnyEvent;
use AnyEvent::Strict;
use AnyEvent::Socket;
use Pogo::Defaults qw(
  $POGO_DISPATCHER_RPC_HOST
  $POGO_DISPATCHER_RPC_PORT
);
use base "Object::Event";

###########################################
sub new {
###########################################
    my($class, %options) = @_;

    my $self = {
        dispatchers => [],
        delay_connect   => sub { 1 },
        delay_reconnect => sub { rand(5) },
        %options,
    };

    bless $self, $class;
}

###########################################
sub start {
###########################################
    my( $self ) = @_;

    DEBUG "Connecting to all dispatchers after ",
          $self->{ delay_connect }->(), "s delay";

    my $timer;
    $timer = AnyEvent->timer(
        after => $self->{ delay_connect }->(),
        cb    => sub {
            undef $timer;
            $self->start_delayed();
        }
    );
}

###########################################
sub start_delayed {
###########################################
    my( $self ) = @_;

    DEBUG "Connecting to all dispatchers";

    for my $dispatcher ( @{ $self->{ dispatchers } } ) {

        my( $host, $port ) = split /:/, $dispatcher;

        DEBUG "Connecting to dispatcher $host:$port";

        tcp_connect( $host, $port, 
                     $self->_connect_handler( $host, $port ) );
    }
}

###########################################
sub _connect_handler {
###########################################
    my( $self, $host, $port ) = @_;

    return sub {
        my ( $fh, $_host, $_port, $retry ) = @_;

        if( !defined $fh ) {
            ERROR "Connect to $host:$port failed: $!";
            return;
        }

        $self->{dispatcher_handle} = AnyEvent::Handle->new(
            fh       => $fh,
            on_error => sub { 
                my ( $hdl, $fatal, $msg ) = @_;

                ERROR "Cannot connect to $host:$port: $msg";
            },
            on_eof   => sub { 
                my ( $hdl ) = @_;
            },
        );
    };
}

1;

__END__

=head1 NAME

Pogo::Worker::Connection - Pogo worker connection abstraction

=head1 SYNOPSIS

    use Pogo::Worker::Connection;

    my $con = Pogo::Worker::Connection->new();

    $con->enable_ssl();

    $con->reg_cb(
      on_connect => sub {},
      on_request => sub {},
    );

    $con->connect( "localhost", 9997 );

=head1 DESCRIPTION

=head1 METHODS

=over 4

=item C<new()>

Constructor.

    my $worker = Pogo::Worker::Connection->new();

=back

=head1 LICENSE

Copyright (c) 2010-2012 Yahoo! Inc. All rights reserved.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
imitations under the License.

=head1 AUTHORS

Mike Schilli <m@perlmeister.com>
Ian Bettinger <ibettinger@yahoo.com>

Many thanks to the following folks for implementing the
original version of Pogo: 

Andrew Sloane <andy@a1k0n.net>, 
Michael Fischer <michael+pogo@dynamine.net>,
Nicholas Harteau <nrh@hep.cat>,
Nick Purvis <nep@noisetu.be>,
Robert Phan <robert.phan@gmail.com>,
Srini Singanallur <ssingan@yahoo.com>,
Yogesh Natarajan <yogesh_ny@yahoo.co.in>

