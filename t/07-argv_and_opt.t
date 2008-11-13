use Test::More tests => 17;

SKIP: {
    eval "use File::Temp qw{ tempfile tempdir }";
    skip "File::Temp not installed", 13 if $@;

    my ($fh, $filename) = tempfile(UNLINK => 1);
    diag("using temporary program file '$filename' to test functionality");

    my $contents = <<'EOT';
use App::Rad;
App::Rad->run();

sub test1 {
    my $c = shift;

    my $ret = scalar (@ARGV) . ' ';
    $ret .= join (' ', @ARGV) . ' ';

    $ret .= scalar @{$c->argv} . ' ';

    $ret .= join (' ', @{$c->argv}) . ' ';

    $ret .= scalar (keys (%{$c->options}));

    foreach (sort keys %{$c->options}) {
        $ret .= ' ' . $_;
        if ($c->options->{$_}) {
            $ret .= ':' . $c->options->{$_};   # key:value
        }
    }

    return $ret . ' '; # space required to avoid
                       # testing the "\n" from post_process()
}
EOT

    print $fh $contents;
    close $fh;
   
    my $ret = `$^X $filename test1 bla -abc --def --test1=2 --test2=test ble`;

    my @ret = split / /, $ret;

    is($ret[0], 6, 'number of elements in @ARGV');
    is($ret[1], 'bla');
    is($ret[2], '-abc');
    is($ret[3], '--def');
    is($ret[4], '--test1=2');
    is($ret[5], '--test2=test');
    is($ret[6], 'ble');

    is($ret[7], 2, 'number of elements in $c->argv');

    # argv testing
    is($ret[8], 'bla');
    is($ret[9], 'ble');

    is($ret[10], 6, 'number of options');

    # options testing (sorted alfabetically)
    is($ret[11], 'a');
    is($ret[12], 'b');
    is($ret[13], 'c');
    is($ret[14], 'def');
    is($ret[15], 'test1:2');
    is($ret[16], 'test2:test');
}
