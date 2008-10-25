use Test::More tests => 3;

SKIP: {
    eval { use File::Temp qw{ tempfile tempdir } };
    skip "File::Temp not installed", 3 if $@;

    my ($fh, $filename) = tempfile(UNLINK => 1);
    diag("using temporary program file '$filename' to test functionality");

    my $contents = <<'EOT';
use App::Rad;
App::Rad->run();

sub test1 {
    my $c = shift;
    if ($c->argv->[0]) {
        return 'got ' . $c->argv->[0];
    }
    else {
        return 'my test #1';
    }
}
EOT

    print $fh $contents;
    close $fh;
   
    my $ret = `perl $filename`;


my $helptext = <<"EOHELP";
Usage: $filename command [arguments]

Available Commands:
   test1
   help

EOHELP

    is($ret, $helptext);


    $ret = '';
    $ret = `perl $filename test1`;
    is($ret, "my test #1\n");

    $ret = '';
    $ret = `perl $filename test1 tested`;
    is($ret, "got tested\n");
}
