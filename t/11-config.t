use Test::More tests => 10;

SKIP: {
    eval "use File::Temp qw{ tempfile tempdir } ";
    skip "File::Temp not installed", 10 if $@;

    my ($fh, $filename) = tempfile(UNLINK => 1);
    diag("using temporary program file '$filename' to test functionality");
    my ($fh_cfg1, $filename_cfg1) = tempfile(UNLINK => 1);
    diag("using temporary stub config file '$filename_cfg1'");
    my ($fh_cfg2, $filename_cfg2) = tempfile(UNLINK => 1);
    diag("using temporary stub config file '$filename_cfg1'");

my $cfg1 = <<'EOCFG';
um one

dois        two
tres:three


quatro   :    four
# coment=yes!
cinco=five   # inline comments too!
                
seis     =        six
EOCFG
print $fh_cfg1 $cfg1;
close $fh_cfg1;

my $cfg2 = <<'EOCFG';
cinco=sinc
  seis     =        six    
sete      


EOCFG
print $fh_cfg2 $cfg2;
close $fh_cfg2;


    my $contents = <<"EOT";
use App::Rad;
App::Rad->run();

sub setup {
    my \$c = shift;
    \$c->load_config('$filename_cfg1');
    \$c->load_config(qw($filename_cfg1 $filename_cfg2));
    \$c->register_commands();
}

sub config_test {
    my \$c = shift;

    \$c->config->{'oito'} = 'eight';

    my \$ret = scalar (keys (\%{\$c->config})) . \$/;
    foreach (sort (keys \%{\$c->config})) {
        \$ret .= \$_ . ':';
        if (\$c->config->{\$_}) {
            \$ret .= \$c->config->{\$_};
        }
        \$ret .= \$/;
    }
    return \$ret;
}

EOT

    print $fh $contents;
    close $fh;
   
    my $ret = `$^X $filename config_test`;
    my @ret = split m{$/}, $ret;
    is(scalar (@ret), 9);
    is($ret[0], '8');
    is($ret[1], 'cinco:sinc');
    is($ret[2], 'dois:two');
    is($ret[3], 'oito:eight');
    is($ret[4], 'quatro:four');
    is($ret[5], 'seis:six');
    is($ret[6], 'sete:');
    is($ret[7], 'tres:three');
    is($ret[8], 'um:one');
}
