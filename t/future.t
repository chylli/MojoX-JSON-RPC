#!/usr/bin/env perl

use strict;
use warnings;
use File::Basename 'dirname';
use File::Spec;

use lib join '/', File::Spec->splitdir( dirname(__FILE__) ), 'lib';
use lib join '/', File::Spec->splitdir( dirname(__FILE__) ), '..', 'lib';

#-------------------------------------------------------------------

# Define custom service
package MyService;

use Mojo::Base 'MojoX::JSON::RPC::Service';
use Future;
use Future::Mojo;
use Mojo::IOLoop::ReadWriteFork;
sub future_done {
    my ($self) = @_;
    return Future->new->done('future done');
}

sub future_fail {
  my ($self) = @_;
  return Future->new->fail('future fail');
}

sub bash_echo {
      my ( $self, @params ) = (@_, '');

      my $future = Future::Mojo->new;
      my $fork   = Mojo::IOLoop::ReadWriteFork->new;
      my $output = '';
      my $n      = 0;
      my $closed = 0;
      warn "bash_echo called";
      $fork->on(
                error => sub {
                  my ($fork, $error) = @_;
                  $future->fail("bash fail error $error");
                  warn "error $error";
                }
               );
      $fork->on(
                close => sub {
                  my ($fork, $exit_value, $signal) = @_;
                  warn "close";
                  if ($exit_value){
                    $future->fail("Exit code $exit_value", fork => exitcode => $exit_value);
                  }
                  else {
                    $future->done($output);
                  }
                }
               );
      $fork->on(
                read => sub {
                  my ($fork, $buffer, $writer) = @_;
                  $output .= $buffer;
                  warn "reading";
                }
               );

      $fork->start(program => 'bash', program_args => [-c => "echo $params[0] foo bar baz"], conduit => 'pty',);
      #Mojo::IOLoop->start unless Mojo::IOLoop->is_running;
      return $future;
}

__PACKAGE__->register_rpc_method_names(
    'future_done', 'future_fail', 'bash_echo',
);

#-------------------------------------------------------------------

# Mojolicious app for testing
package MojoxJsonRpc;

use Mojo::Base 'Mojolicious';

use MojoX::JSON::RPC::Service;
# This method will run once at server start
sub startup {
  my $self = shift;

  $self->secrets(['Testing!']);

  $self->plugin(
                'json_rpc_dispatcher',
                services => {
                             '/jsonrpc' => MyService->new
                            }
               );
}
#-------------------------------------------------------------------

# Back to tests
  package main;

  use TestUts;

  use Test::More tests => 5;
  use Test::Mojo;

use_ok 'MojoX::JSON::RPC::Service';
use_ok 'MojoX::JSON::RPC::Client';

my $t = Test::Mojo->new('MojoxJsonRpc');
my $client = MojoX::JSON::RPC::Client->new( ua => $t->ua );

# test Future done
TestUts::test_call(
                   $client,
                   '/jsonrpc',
                   {   id     => 1,
                       method => 'future_done',
                   },
                   {   result => 'future done',
                       id     => 1
                   },
                   'future'
                  );

# test Future fail
TestUts::test_call(
                   $client,
                   '/jsonrpc',
                   {   id     => 1,
                       method => 'future_fail',
                   },
                   {   result => 'future fail',
                       id     => 1
                   },
                   'future'
                  );

# test future ioloop
TestUts::test_call(
                   $client,
                   '/jsonrpc',
                   {   id     => 1,
                       method => 'bash_echo',
                       params => ["hello"],
                   },
                   {   result => 'bash_echo',
                       id     => 1
                   },
                   'bash_echo'
                  );


