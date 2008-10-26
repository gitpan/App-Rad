use Test::More tests => 8;

SKIP: {
    eval "use Getopt::Long 2.36";
    skip "Getopt::Long 2.36 or higher not installed", 8, if $@;

    eval "use File::Temp qw{ tempfile tempdir } ";
    skip "File::Temp not installed", 8 if $@;

    my ($fh, $filename) = tempfile(UNLINK => 1);
    diag("using temporary program file '$filename' to test functionality");

    my $contents = <<'EOT';
use App::Rad;
App::Rad->run();

sub pre_process {
    my $c = shift;

    $c->getopt(
            'igoo|i=s',
            'tundro|t=i',
            'zok|z=f',
            'glup',
            'glip',
            'a',
            'b',
            'c',
        );
}


sub herculoids {
    my $c = shift;

    my $ret = scalar (keys (%{$c->options}));

    foreach (sort keys %{$c->options}) {
        $ret .= ' ' . $_ . ':' . $c->options->{$_};   # key:value
    }

    return $ret . ' '; # space required to avoid
                       # testing the "\n" from post_process()
}
EOT

    print $fh $contents;
    close $fh;
   
    my $ret = `$^X $filename herculoids --igoo=ape -t 4 --zok=3.14 --glup -abc`;

    my @ret = split / /, $ret;

    is($ret[0], 7, 'number of options');

    # options testing (sorted alfabetically)
    is($ret[1], 'a:1');
    is($ret[2], 'b:1');
    is($ret[3], 'c:1');
    is($ret[4], 'glup:1');
    is($ret[5], 'igoo:ape');
    is($ret[6], 'tundro:4');
    is($ret[7], 'zok:3.14');
}
