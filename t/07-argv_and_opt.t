use Test::More tests => 13;

SKIP: {
    eval { use File::Temp qw{ tempfile tempdir } };
    skip "File::Temp not installed", 13 if $@;

    my ($fh, $filename) = tempfile(UNLINK => 1);
    diag("using temporary program file '$filename' to test functionality");

    my $contents = <<'EOT';
use App::Rad;
App::Rad->run();

sub test1 {
    my $c = shift;

    my $ret = scalar @{$c->argv} . ' ';

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
   
    my $ret = `$^X $filename test1 bla -abc --def --test1=2 --test2=test`;

    my @ret = split / /, $ret;
    is($ret[0], 5, 'number of elements');

    # argv testing
    is($ret[1], 'bla');
    is($ret[2], '-abc');
    is($ret[3], '--def');
    is($ret[4], '--test1=2');
    is($ret[5], '--test2=test');

    is($ret[6], 6, 'number of options');

    # options testing (sorted alfabetically)
    is($ret[7], 'a');
    is($ret[8], 'b');
    is($ret[9], 'c');
    is($ret[10], 'def');
    is($ret[11], 'test1:2');
    is($ret[12], 'test2:test');
}
