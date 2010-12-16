package PogoTester;

# Copyright (c) 2010, Yahoo! Inc. All rights reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

use common::sense;

use Time::HiRes qw(sleep);
use Log::Log4perl qw(:easy);

use AnyEvent;
use AnyEvent::Handle;
use AnyEvent::Socket qw(tcp_connect);
use AnyEvent::TLS;
use YAML::XS qw(LoadFile);
use Net::SSLeay;
use Data::Dumper;
use Carp qw(croak confess);
use Exporter 'import';
use FindBin qw($Bin);
use Template;
use LWP;

our $dispatcher_pid;

use constant ZOO_PID_FILE => "$Bin/.tmp/zookeeper.pid";

# path to apache2 httpd
use constant HTTPD_BIN => '/opt/local/apache2/bin/httpd';

# apache2 ServerRoot, our conf will include modules form HTTPD_ROOT/modules/
use constant HTTPD_ROOT => '/opt/local/apache2';

# port to run the test instance on
use constant HTTPD_PORT => 9414;

our @EXPORT_OK = qw(derp);

sub new
{
  my ( $class, %opts ) = @_;
  mkdir "$Bin/.tmp"
    unless -d "$Bin/.tmp";
  mkdir "$Bin/.tmp/pogo_output"
    unless -d "$Bin/.tmp/pogo_output";
  mkdir "$Bin/.tmp/apache"
    unless -d "$Bin/.tmp/apache";

  $Pogo::Common::CONFIGDIR = "$Bin/conf/";

  my $conf = $opts{conf} || "$Bin/conf/dispatcher.conf";
  my $self = LoadFile($conf);

  # use the anyevent stuff here even though we don't need to be
  # event-driven in the test suite.  we want to use the same
  # client code we normally do.
  $self->{worker_ctx} = AnyEvent::TLS->new(
    key_file                   => "$Bin/conf/worker.key",
    cert_file                  => "$Bin/conf/worker.cert",
    verify_require_client_cert => 1,
    verify                     => 0,
  ) || LOGDIE "Couldn't init: $!";
  $self->{authstore_ctx} = AnyEvent::TLS->new(
    key_file                   => "$Bin/conf/authstore.key",
    cert_file                  => "$Bin/conf/authstore.cert",
    verify_require_client_cert => 1,
    verify                     => 0,
  ) || LOGDIE "Couldn't init: $!";
  $self->{dispatcher_ctx} = AnyEvent::TLS->new(
    key_file                   => "$Bin/conf/dispatcher.key",
    cert_file                  => "$Bin/conf/dispatcher.cert",
    verify_require_client_cert => 1,
    verify                     => 0,
  ) || LOGDIE "Couldn't init: $!";

  $self->{bind_address} ||= '127.0.0.1';

  return bless $self, $class;
}

sub start_dispatcher
{
  my ( $self, %opts ) = @_;
  my $conf = $opts{conf} || "$Bin/conf/dispatcher.conf";
  $dispatcher_pid = fork();

  if ( $dispatcher_pid == 0 )
  {
    exec( "/usr/bin/env", "perl", "-I$Bin/../lib", "-I$Bin/lib", "$Bin/../bin/pogo-dispatcher",
      '-f', $conf )
      or LOGDIE $!;
  }
  else
  {
    sleep(2.5);
    INFO "spawned dispatcher (pid $dispatcher_pid)";
  }

  return $dispatcher_pid;
}

sub stop_dispatcher
{
  my $self = shift;
  sleep(0.2);
  INFO "killing $dispatcher_pid";
  kill( 15, $dispatcher_pid );
  return 1;
}

sub start_zookeeper
{
  my ( $self, %opts ) = @_;
  my $conf = $opts{zookeeper_conf} || "$Bin/conf/zookeeper.conf";
  my $zookeeper_pid = fork();

  my $zookeeper_cmd = `$Bin/../build/zookeeper/bin/zkServer.sh print-cmd $conf 2>/dev/null`;
  DEBUG "using '$zookeeper_cmd'";

  if ( $zookeeper_pid == 0 )
  {

    #open STDIN, '/dev/null';
    open STDOUT, '>/dev/null';
    open STDERR, '>&STDOUT';

    close STDIN;
    exec($zookeeper_cmd)
      or LOGDIE "$zookeeper_cmd failed: $!";
  }
  else
  {
    sleep(2.5);
    INFO "spawned zookeeper (pid $zookeeper_pid)";
    open my $fh, '>', ZOO_PID_FILE
      or LOGDIE "couldn't open file: $!";

    print $fh $zookeeper_pid;
    close $fh;
  }

  return 1;
}

sub stop_zookeeper
{
  my $self = shift;
  sleep(0.2);

  return unless -r ZOO_PID_FILE;

  open my $fh, '<', ZOO_PID_FILE
    or LOGDIE "couldn't open file: $!";

  chomp( my $zookeeper_pid = <$fh> );
  close $fh;

  if ( !defined $zookeeper_pid || $zookeeper_pid !~ /^\d+$/ )
  {
    LOGDIE "invalid pid: $zookeeper_pid";
  }

  INFO "killing $zookeeper_pid";
  kill( 15, $zookeeper_pid );
  unlink ZOO_PID_FILE;
  return 1;
}

# send raw json-rpc back and forth to our authstore port
sub authstore_rpc
{
  my ( $self, $rpc ) = @_;
  my $cv = AnyEvent->condvar;
  if ( !defined $self->{authstore_handle} )
  {
    DEBUG "creating new authstore handle";
    tcp_connect(
      $self->{bind_address},
      $self->{authstore_port},
      sub {
        my ( $fh, $host, $port ) = @_;
        if ( !$host && !$port )
        {
          ERROR "connection failed: $!";
          return;
        }
        DEBUG "connection successful, starting SSL negotiation";
        $self->{authstore_handle} = AnyEvent::Handle->new(
          fh       => $fh,
          tls      => 'connect',
          tls_ctx  => $self->{authstore_ctx},
          no_delay => 1,
          on_eof   => sub {
            delete $self->{authstore_handle};
            INFO "connection closed to $host:$port";
          },
          on_error => sub {
            delete $self->{authstore_handle};
            my $fatal = $_[1];
            LOGDIE
              sprintf( "$host:$port reported %s error: %s", $fatal ? 'fatal' : 'non-fatal', $! );
          },
        ) || LOGDIE "couldn't create handle: $!";
        $self->{authstore_handle}->push_write( json => $rpc );
        $self->{authstore_handle}->push_read( json => sub { $cv->send( $_[1] ); }, );
      },
    );
  }
  else
  {
    $self->{authstore_handle}->push_write( json => $rpc );
    $self->{authstore_handle}->push_read( json => sub { $cv->send( $_[1] ); }, );
  }

  return $cv->recv;
}

sub dispatcher_rpc
{
  my ( $self, $rpc ) = @_;
  my $cv = AnyEvent->condvar;
  if ( !defined $self->{dispatcher_handle} )
  {
    DEBUG "creating new dispatcher handle: $self->{bind_address}:$self->{rpc_port}";
    tcp_connect(
      $self->{bind_address},
      $self->{rpc_port},
      sub {
        local *__ANON__ = 'AE:cb:connect_cb';
        my ( $fh, $host, $port ) = @_;
        if ( !$host && !$port )
        {
          LOGDIE "connection failed: $!";
        }
        DEBUG "connection successful, starting SSL negotiation";
        $self->{dispatcher_handle} = AnyEvent::Handle->new(
          fh       => $fh,
          tls      => 'connect',
          tls_ctx  => $self->{dispatcher_ctx},
          no_delay => 1,
          on_eof   => sub {
            delete $self->{dispatcher_handle};
            INFO "connection closed to $host:$port";
          },
          on_error => sub {
            delete $self->{dispatcher_handle};
            my $fatal = $_[1];
            LOGDIE
              sprintf( "$host:$port reported %s error: %s", $fatal ? 'fatal' : 'non-fatal', $! );
          },
        ) || LOGDIE "couldn't create handle: $!";
        $self->{dispatcher_handle}->push_write( json => $rpc );
        $self->{dispatcher_handle}->push_read( json => sub { $cv->send( $_[1] ); }, );
      },
    );
  }
  else
  {
    $self->{dispatcher_handle}->push_write( json => $rpc );
    $self->{dispatcher_handle}->push_read( json => sub { $cv->send( $_[1] ); }, );
  }

  return $cv->recv;
}

sub worker_rpc
{
  my ( $self, $rpc ) = @_;
  my $cv = AnyEvent->condvar;
  if ( !defined $self->{worker_handle} )
  {
    DEBUG "creating new worker handle";
    tcp_connect(
      $self->{bind_address},
      $self->{worker_port},
      sub {
        my ( $fh, $host, $port ) = @_;
        if ( !$host && !$port )
        {
          ERROR "connection failed: $!";
          return;
        }
        DEBUG "connection successful, starting SSL negotiation";
        $self->{worker_handle} = AnyEvent::Handle->new(
          fh       => $fh,
          tls      => 'connect',
          tls_ctx  => $self->{worker_ctx},
          no_delay => 1,
          on_eof   => sub {
            delete $self->{worker_handle};
            INFO "connection closed to $host:$port";
          },
          on_error => sub {
            delete $self->{worker_handle};
            my $fatal = $_[1];
            LOGDIE
              sprintf( "$host:$port reported %s error: %s", $fatal ? 'fatal' : 'non-fatal', $! );
          },
        ) || LOGDIE "couldn't create handle: $!";
        $self->{worker_handle}->push_write( json => $rpc );
        $self->{worker_handle}->push_read( json => sub { $cv->send( $_[1] ); }, );
      },
    );
  }
  else
  {
    $self->{worker_handle}->push_write( json => $rpc );
    $self->{worker_handle}->push_read( json => sub { $cv->send( $_[1] ); }, );
  }

  return $cv->recv;
}

# check whether httpd exists
sub httpd_exists
{
  my ($self) = @_;
  return -x HTTPD_BIN;
}

# check the configured httpd to make sure it's the correct version
sub check_httpd_version
{
  my ( $self, $httpd ) = @_;
  my $httpd = HTTPD_BIN;
  chomp( my ($verline) = grep {/Server version:/} `$httpd -v` );
  return defined $verline && $verline =~ m/Apache\/2\./;
}

# build the httpd.conf we'll use to start the test httpd
sub build_httpd_conf
{
  my ( $self, $Bin ) = @_;

  my $root = HTTPD_ROOT;

  my $conf_dir  = "$Bin/.tmp/apache";
  my $conf_file = "$conf_dir/httpd.conf";

  my $t = Template->new( { INCLUDE_PATH => "$Bin/conf" } );

  my $template_params = {
    'include_root'  => $root,
    'server_root'   => "$Bin/",
    'document_root' => "$Bin/htdocs",
    'perl_lib'      => "$Bin/../lib",
    'template_dir'  => "$Bin/../templates",
    'log_dir'       => "$Bin/.tmp/apache/",
    'httpd_port'    => HTTPD_PORT(),
    'httpd_user'    => scalar( getpwuid($>) ),
    'httpd_group'   => scalar( getgrgid($)) ),
    'config_dir'    => $Pogo::Common::CONFIGDIR
  };

  INFO "creating conf_file $conf_file";
  open( my $FH, ">$conf_file" ) || LOGDIE "Unable to open $conf_file for writing: $!";
  print $t->process( 'httpd.conf.tpl', $template_params, $FH );
  close($FH);

  return sprintf( 'http://localhost:%s/', HTTPD_PORT );
}

# start our test httpd instance
sub start_httpd
{
  my ( $self, $Bin ) = @_;

  my $httpd = HTTPD_BIN;

  my $conf_file = "$Bin/.tmp/apache/httpd.conf";
  my $pid_file  = "$Bin/.tmp/apache/httpd.pid";
  if ( -e $pid_file )
  {
    ERROR "pid_file $pid_file exists! is apache already running?";
    return;
  }

  if ( !-r $conf_file )
  {
    ERROR "conf_file $conf_file missing or unreadable";
    return;
  }

  my $res = system( $httpd, '-f', $conf_file );
  sleep 0.25;
  return $res == 0 ? 1 : 0;
}

# stop our test httpd instance
sub stop_httpd
{
  my ( $self, $Bin ) = @_;

  my $pid_file = "$Bin/.tmp/apache/httpd.pid";
  if ( !-r $pid_file )
  {
    ERROR "pid_file $pid_file missing or unreadable";
    return;
  }

  open( my $FH, '<', $pid_file ) || LOGDIE "Unable to open $pid_file for reading: $!";
  chomp( my $httpd_pid = <$FH> );
  close($FH);

  INFO "killing $httpd_pid";
  kill( 15, $httpd_pid );
  sleep 0.25;

  return 1;
}

# check that our test httpd instance is online
sub check_httpd
{
  my ($self) = @_;

  my $ua = LWP::UserAgent->new();
  my $res = $ua->get( sprintf( "http://localhost:%d/index.html", HTTPD_PORT ) );
  return ( $res && $res->is_success && $res->decoded_content =~ m/^POGO_OK/ );
}

# pretty-print a test failure
sub derp
{
  my ( $test, $obj ) = @_;
  my $dump = Data::Dumper::Dumper($obj);
  my $str  = <<"__DERP__";
Test name: $test
Result: $dump
__DERP__

  return $str;
}

1;

=pod

=head1 NAME

  CLASSNAME - SHORT DESCRIPTION

=head1 SYNOPSIS

CODE GOES HERE

=head1 DESCRIPTION

LONG_DESCRIPTION

=head1 METHODS

B<methodexample>

=over 2

methoddescription

=back

=head1 SEE ALSO

L<Pogo::Dispatcher>

=head1 COPYRIGHT

Apache 2.0

=head1 AUTHORS

  Andrew Sloane <asloane@yahoo-inc.com>
  Michael Fischer <mfischer@yahoo-inc.com>
  Nicholas Harteau <nrh@yahoo-inc.com>
  Nick Purvis <nep@yahoo-inc.com>
  Robert Phan <rphan@yahoo-inc.com>

=cut

# vim:syn=perl:sw=2:ts=2:sts=2:et:fdm=marker
