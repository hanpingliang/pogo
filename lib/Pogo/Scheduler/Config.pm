###########################################
package Pogo::Scheduler::Config;
###########################################
use strict;
use warnings;
use Log::Log4perl qw(:easy);
use AnyEvent;
use AnyEvent::Strict;
use Pogo::Scheduler::Constraint;
use Data::Dumper;
use YAML qw( Load LoadFile );
use base qw(Pogo::Object::Event);

use Pogo::Util qw( make_accessor id_gen struct_traverse );
__PACKAGE__->make_accessor( $_ ) for qw( );

use overload ( 'fallback' => 1, '""' => 'as_string' );

###########################################
sub new {
###########################################
    my ( $class, %options ) = @_;

    my $self = {
        cfg  => {},
        tags => {},
        %options,
    };

    bless $self, $class;
}

###########################################
sub load {
###########################################
    my ( $self, $yaml ) = @_;

    $self->{ cfg } = Load( $yaml );
    $self->parse();
}

###########################################
sub load_file {
###########################################
    my ( $self, $yaml_file ) = @_;

    $self->{ cfg } = LoadFile( $yaml_file );
    $self->parse();
}

###########################################
sub parse {
###########################################
    my ( $self ) = @_;

    Pogo::Util::struct_traverse(
        $self->{ cfg }->{ tag },
        {   leaf => sub {
                my ( $node, $path ) = @_;

                $path =~ s/^\$//;
                my @parts = split /\./, $path;

                for my $part ( @parts ) {
                }

                DEBUG "node=$node path=", Dumper( $path );
            }
        }
    );
}

###########################################
sub members {
###########################################
    my ( $self, $tag ) = @_;

    if( !exists $self->{ tags }->{ $tag } ) {
        return ();
    }

    return $self->{ tags }->{ $tag }->members();
}

###########################################
sub as_string {
###########################################
    my ( $self ) = @_;

    local $Data::Dumper::Indent;
    $Data::Dumper::Indent = 0;
    return Dumper( $self->{ cfg } );
}

1;

__END__

=head1 NAME

Pogo::Scheduler::Config - Pogo scheduler configuration handling

=head1 SYNOPSIS

    use Pogo::Scheduler::Config;
    
    my $slot = Pogo::Scheduler::Config->new();
    
=head1 DESCRIPTION

    use Pogo::Scheduler::Config;

    my $cfg = Pogo::Scheduler::Config->new();
    $cfg->load( <<'EOT' );
      tag:
         $colo.usa
           - host1
         $colo.mexico
           - host2
    EOT

    my @all = $cfg->members( "colo" );           # host1, host2
    my @mexico = $cfg->members( "colo.mexico" ); # host2

=head2 METHODS

=over 4

=item C< load( $yaml ) >

Load a scheduler configuration from a YAML string.

=item C< load_file( $yaml_file ) >

Load a YAML scheduler configuration from a YAML file.

=item C< members( $tag ) >

Return all members of the tag.

members( "Role(devtools.infra-ops)" );

=> my $plugin = Pogo::Scheduler::Config::Plugins::Role->new();
   $plugin->targets( "devtools.infra-ops" );
     => rolesdb API members( "devtools.infra-ops" );

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

