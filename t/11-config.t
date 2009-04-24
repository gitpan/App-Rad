use FindBin;
my $path = $FindBin::RealBin . '/etc';
use Test::More tests => 9;

use App::Rad;

# kids, don't try this at home...
my $c = {};
bless $c, 'App::Rad';
$c->_init();

$c->load_config("$path/config1.txt");
$c->load_config("$path/config1.txt",
                "$path/config2.txt"
               );

$c->config->{'oito'} = 'eight';

is(keys( %{$c->config} ), 8, 'load_config() should have loaded 8 unique elements');
is($c->config->{'um'    }, 'one'  , 'config value mismatch');
is($c->config->{'dois'  }, 'two'  , 'config value mismatch');
is($c->config->{'tres'  }, 'three', 'config value mismatch');
is($c->config->{'quatro'}, 'four' , 'config value mismatch');
is($c->config->{'cinco' }, 'sinc' , 'config value mismatch');
is($c->config->{'seis'  }, 'six'  , 'config value mismatch');
ok(exists $c->config->{'sete'}, 'unary values must exist');
is($c->config->{'oito'  }, 'eight', 'should be able to define values in running code');
