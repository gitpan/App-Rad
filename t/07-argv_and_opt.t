use Test::More tests => 16;

use App::Rad;

@ARGV = qw(commandname bla -abc --def --test1=2 --test2=test ble);

# kids, don't try this at home...
my $c = {};
bless $c, 'App::Rad';
$c->_init();
$c->_get_input();

is(scalar @ARGV, 6, '@ARGV should have 6 elements');
is(scalar @{$c->argv}, 2, '$c->argv should have 2 arguments');
is(keys %{$c->options}, 6, '$c->options should have 6 elements');

is($c->cmd, 'commandname', 'command name should be set');

is_deeply(\@ARGV, ['bla', '-abc', '--def', '--test1=2', '--test2=test', 'ble'], 
   '@ARGV should have just the passed arguments, not the command name'
  );

is_deeply($c->argv, ['bla', 'ble'], '$c->argv arguments should be consistent');
ok(defined $c->options->{'a'}, "'-a' should be set");
ok(defined $c->options->{'b'}, "'-a' should be set");
ok(defined $c->options->{'c'}, "'-a' should be set");

ok(!defined $c->options->{'abc'}, "'--abc' should *not* be set");
ok(!defined $c->options->{'d'}  , "'-d' should *not* be set");
ok(!defined $c->options->{'e'}  , "'-e' should *not* be set");
ok(!defined $c->options->{'f'}  , "'-f' should *not* be set");

ok(defined $c->options->{'def'}, "'--def' should be set");
is($c->options->{'test1'}, 2, "'--test1' should be set to '2'");
is($c->options->{'test2'}, 'test', "'--test2' should be set to 'test'");
