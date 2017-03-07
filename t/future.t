#!/usr/bin/env perl

use strict;
use warnings;
use File::Basename 'dirname';
use File::Spec;

use Test::More;

use MojoX::JSON::RPC::Service;
use MojoX::JSON::RPC::Client;

use lib join '/', File::Spec->splitdir( dirname(__FILE__) ), 'lib';
use lib join '/', File::Spec->splitdir( dirname(__FILE__) ), '..', 'lib';

eval {
    require Future;
    require Future::Mojo;
} or plan skip_all => 'needs Future and Future::Mojo modules';

#-------------------------------------------------------------------

{
# Define custom service
package MyService;

use Mojo::Base 'MojoX::JSON::RPC::Service';

sub provide {
    my ($name, $code) = @_;
    Mojo::Util::monkey_patch(__PACKAGE__, $name => $code);
    __PACKAGE__->register_rpc_method_names($name);
}

provide echo => sub {
    my ( $self, @params ) = @_;

    return $params[0];
};


provide immediate_success => sub {
    my ($self) = @_;
    return Future->done('future done');
};

provide immediate_fail => sub {
  my ($self) = @_;
  return Future->fail('failure message', 'rpc');
};

provide deferred_fail => sub {
  my ($self) = @_;
    my $f = Future::Mojo->new;
    Mojo::IOLoop->timer(0.5 => sub { $f->fail('deferred failure') });
    return $f;
};

provide deferred_success => sub {
    my ($self) = @_;
    my $f = Future::Mojo->new;
    Mojo::IOLoop->timer(0.5 => sub { $f->done('deferred ok') });
    return $f;
};

provide bash_echo => sub {
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
      #$fork->start(program => '/bin/touch', program_args => ["/tmp/test.log"]);
      return $future;
};


}

#-------------------------------------------------------------------

{
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

}

#-------------------------------------------------------------------

# Back to tests
use TestUts;

use Test::Mojo;

my $t = Test::Mojo->new('MojoxJsonRpc');
my $client = MojoX::JSON::RPC::Client->new( ua => $t->ua );

note 'simple echo';
TestUts::test_call(
    $client,
    '/jsonrpc',
    {   id     => 2,
        method => 'echo',
        params => ['HEEEEEEEEEEEEEEEEELLLLLLLLLLLLLLLOOOOOOOOOOO!']
    },
    {   result => 'HEEEEEEEEEEEEEEEEELLLLLLLLLLLLLLLOOOOOOOOOOO!',
        id     => 2
    },
    'echo 1'
);

# test Future done

note 'immediate success';
TestUts::test_call(
    $client,
    '/jsonrpc',
    {   id     => 1,
        method => 'immediate_success',
    },
    {   result => 'future done',
        id     => 1
    },
    'future'
);

note 'deferred success, should take half a second';
TestUts::test_call(
    $client,
    '/jsonrpc',
    {   id     => 1,
        method => 'deferred_success',
    },
    {   result => 'deferred ok',
        id     => 1
    },
    'deferred success future'
);

TestUts::test_call(
    $client,
    '/jsonrpc',
    {   id     => 1,
        method => 'immediate_fail',
    },
    {   error  => { message => 'failure message', code => '', data => '' },
        id     => 1
    },
    'immediate_fail'
);

TestUts::test_call(
    $client,
    '/jsonrpc',
    {   id     => 1,
        method => 'deferred_fail',
    },
    {   error  => { message => 'deferred failure', code => '', data => '' },
        id     => 1
    },
    'deferred_fail'
);

my $in_string = "hello";
my $out_string;

#$client->call(
#              '/jsonrpc',
#              {   id     => 2,
#                  method => 'bash_echo',
#                  params => [ $in_string ]
#              },
#              sub {
#                Mojo::IOLoop->stop;
#                my $res = pop;
#                $out_string = $res->result;
#              }
#             );
#
#Mojo::IOLoop->start unless Mojo::IOLoop->is_running;
#
#is($out_string, $in_string, 'test future');


TestUts::test_call(
    $client,
    '/jsonrpc',
    {   id     => 2,
        method => 'echo',
        params => ['HEEEEEEEEEEEEEEEEELLLLLLLLLLLLLLLOOOOOOOOOOO!']
    },
    {   result => 'HEEEEEEEEEEEEEEEEELLLLLLLLLLLLLLLOOOOOOOOOOO!',
        id     => 2
    },
    'echo 2'
);

done_testing;

