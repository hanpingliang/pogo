###########################################
package Pogo::Dispatcher;
###########################################
use strict;
use warnings;
use Log::Log4perl qw(:easy);
use AnyEvent;
use AnyEvent::Strict;
use Pogo::Dispatcher::ControlPort;
use Pogo::Dispatcher::Wconn::Pool;
use Pogo::Util qw( jobid_valid );
use Pogo::Util::Cache;
use base qw(Pogo::Object::Event);
use Pogo::Defaults qw(
    $POGO_DISPATCHER_WORKERCONN_HOST
    $POGO_DISPATCHER_WORKERCONN_PORT
    $POGO_DISPATCHER_CONTROLPORT_HOST
    $POGO_DISPATCHER_CONTROLPORT_PORT
);

our $VERSION = "0.01";

###########################################
sub new {
###########################################
    my ( $class, %options ) = @_;

    my $self = {
        next_task_id          => 1,
        password_cache_expire => 300,
        controlport_host      => undef,
        controlport_port      => undef,
        workerconn_host       => undef,
        workerconn_port       => undef,
        %options,
    };

    $self->{ controlport_host } ||= $POGO_DISPATCHER_CONTROLPORT_HOST;
    $self->{ controlport_port } ||= $POGO_DISPATCHER_CONTROLPORT_PORT;
    $self->{ workerconn_host }  ||= $POGO_DISPATCHER_WORKERCONN_HOST;
    $self->{ workerconn_port }  ||= $POGO_DISPATCHER_WORKERCONN_PORT;

    $self->{ password_cache } = Pogo::Util::Cache->new(
        expire => $self->{ password_cache_expire },
    );

    bless $self, $class;

    return $self;
}

###########################################
sub start {
###########################################
    my ( $self ) = @_;

    # Handle a pool of workers, as they connect
    my $w = Pogo::Dispatcher::Wconn::Pool->new( 
        host => $self->{ workerconn_host },
        port => $self->{ workerconn_port },
        map { $_ => $self->{ $_ } }
            qw( ssl dispatcher_cert dispatcher_key ca_cert ),
    );

    $self->event_forward(
        { forward_from => $w }, qw(
            dispatcher_wconn_worker_connect
            dispatcher_wconn_prepare
            dispatcher_wconn_cmd_recv
            dispatcher_wconn_ack )
    );
    $w->start();
    $self->{ wconn_pool } = $w;    # guard it or it'll vanish

    # Listen to requests from the ControlPort
    my $cp = Pogo::Dispatcher::ControlPort->new( 
        dispatcher => $self, 
        host       => $self->{ controlport_host },
        port       => $self->{ controlport_port },
    );
    $self->event_forward(
        { forward_from => $cp }, qw(
            dispatcher_controlport_up )
    );
    $cp->start();
    $self->{ cp } = $cp;           # guard it or it'll vanish

      # if a task for a worker comes in ...
    $self->reg_cb(
        "dispatcher_worker_task_received",
        sub {
            my ( $c, $slot_task, $worker_task_data, $scheduler ) = @_;
             
            # Assign it a dispatcher task ID
            my $id = $self->next_task_id();

            my $task = {
                slot_task        => $slot_task,
                host             => $slot_task->{ host },
                worker_task_data => $worker_task_data,
                task_id          => $id,
                scheduler        => $scheduler,
            };

            $self->{ tasks_in_progress }->{ $id } = $task;

            # ... send it to a worker
            DEBUG "Sending cmd for $task->{ host } to a worker";

            my $to_worker = {
                host      => $slot_task->{ host },
                task_data => $worker_task_data,
                task_id   => $id,
            };

            $self->to_worker( $to_worker );
        }
    );

    $self->reg_cb(
        "dispatcher_wconn_cmd_recv",
        sub {
            my ( $c, $data ) = @_;

            # if a completed task report comes back from a worker
            if ( $data->{ command } eq "task_done" ) {
                DEBUG "Worker reported task $data->{ task_id } done";
                $self->event( "dispatcher_task_done", $data->{ task_id } );

                  # tell the scheduler that the task is done
                  my $task = 
                    $self->{ tasks_in_progress }->{ $data->{ task_id } };
              
                  my $slot_task = $task->{ slot_task };

                  if( $task->{ scheduler } ) {
                      DEBUG "Telling scheduler about task ",
                        "$data->{ task_id } completion";

                      $task->{ scheduler }->event( "task_mark_done", 
                          $slot_task );
                  }

                    # task no longer in progress
                  delete $self->{ tasks_in_progress }->{ $data->{ task_id } };
            }
        }
    );

    DEBUG "Dispatcher started";
}

###########################################
sub next_task_id_base {
###########################################
    my ( $self ) = @_;

    return "$POGO_DISPATCHER_WORKERCONN_HOST:$POGO_DISPATCHER_WORKERCONN_PORT";
}

###########################################
sub next_task_id {
###########################################
    my ( $self ) = @_;

    my $id = $self->{ next_task_id }++;

    return $self->next_task_id_base() . "-$id";
}

###########################################
sub to_worker {
###########################################
    my ( $self, $data ) = @_;

    $self->{ wconn_pool }->event( "dispatcher_wconn_send_cmd", $data );
}

###########################################
sub password_update {
###########################################
    my ( $self, $data ) = @_;

    if( ref $data->{ passwords } ne "HASH" ) {
        ERROR "'passwords' needs to be a hash";
        return 0;
    }

    if( !jobid_valid( $data->{ jobid } ) ) {
        ERROR "invalid job id: $data->{ jobid }";
        return 0;
    }

    $self->event(
        "dispatcher_password_update_received", $data->{ jobid } );

    $self->{ password_cache }->set( 
        $data->{ jobid },
        $data->{ passwords },
    );

    $self->event(
        "dispatcher_password_update_done", $data->{ jobid } );

    DEBUG "Password cache updated for job data->{ jobid } with ",
       scalar keys %{ $data->{ passwords } }, " passwords." ;

    return 1;
}

1;

__END__

=head1 NAME

Pogo::Dispatcher - Pogo Dispatcher Daemon

=head1 SYNOPSIS

    use Pogo::Dispatcher;

    my $worker = Pogo::Dispatcher->new(
      worker_connect  => sub {
          print "Worker $_[0] connected\n";
      },
    );

    Pogo::Dispatcher->start();

=head1 DESCRIPTION

Main code for the Pogo dispatcher daemon. 

Waits for workers to connect.

=head1 METHODS

=over 4

=item C<new()>

Constructor.

=item C<start()>

Starts up the daemon.

=back

=head1 EVENTS

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

