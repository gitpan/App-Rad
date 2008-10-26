use Test::More tests => 3;

SKIP: {
    eval { use File::Temp qw{ tempfile tempdir } };
    skip "File::Temp not installed", 3 if $@;

    my ($fh, $filename) = tempfile(UNLINK => 1);
    diag("using temporary program file '$filename' to test functionality");

    my $contents = <<'EOT';
use App::Rad qw(include exclude);
App::Rad->run();

sub test1 {
    my $c = shift;
    if ($c->{'ARGV'}->[0]) {
        return 'got ' . $c->{'ARGV'}->[0];
    }
    else {
        return 'my test #1';
    }
}
EOT

    print $fh $contents;
    close $fh;
   
    my $ret = `$^X $filename`;


my $helptext = <<"EOHELP";
Usage: $filename command [arguments]

Available Commands:
   test1
   include
   help
   exclude

EOHELP

    is($ret, $helptext);


    $ret = '';
    $ret = `$^X $filename test1`;
    is($ret, "my test #1\n");

    $ret = '';
    $ret = `$^X $filename test1 tested`;
    is($ret, "got tested\n");
}
