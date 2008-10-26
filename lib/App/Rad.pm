package App::Rad;
use warnings;
use strict;
use Carp qw/carp croak/;
use Getopt::Long 2.36 ();

our $VERSION = '0.4';
{

#========================#
#   INTERNAL FUNCTIONS   #
#========================#

my @OPTIONS = ();

sub _init {
    my $c = shift;

    # this is an internal variable that
    # holds the references to all
    # available commands.
    $c->{'_commands'} = {
        'help'         => \&help,
    };

    # this internal variable holds
    # references to all special
    # pre-defined control functions
    $c->{'_functions'} = {
        'setup'        => \&setup,
        'pre_process'  => \&pre_process,
        'post_process' => \&post_process,
        'default'      => \&default,
        'teardown'     => \&teardown,
    };

    foreach (@OPTIONS) {
        if ($_ eq 'include') {
            $c->{'_commands'}->{'include'} = \&include;
        }
        elsif ($_ eq 'exclude') {
            $c->{'_commands'}->{'exclude'} = \&exclude;
        }
        elsif ($_ eq 'debug') {
            $c->{'debug'} = 1;
        }
	}

    $c->{'ARGV'} = [];
    $c->{'_options'} = {};
    $c->{'_stash'} = {};

    $c->debug('initializing: default commands are: '
        . join ( ', ', $c->commands() )
        );
}

sub import {
    my $class = shift;
    @OPTIONS = @_;
}

# this function browses the main
# application's symbol table and maps
# each function to a hash
#
# FIXME: if I create a sub here (Rad.pm) and
# there is a global variable with that same name
# inside the user's program (e.g.: sub ARGV {}),
# the name will appear here as a command. It really 
# shouldn't...
sub _get_main_subs {

    my %subs = ();
    no strict 'refs';

    while (my ($key, $value) = ( each %{*{main::}} )) {
        local (*SYMBOL) = $value;
        if ( defined $value && defined *SYMBOL{CODE} ) {
            $subs{$key} = $value;
        }
    }
    return %subs;
}

# translates one-liner into
# a complete, readable code
sub _get_oneliner_code {
    my $arg_ref = shift;
    my $code =  _sanitize ( _deparse($arg_ref) );
    return $code;
}


#TODO: option to do it saving a backup file
# (behavior probably set via 'setup')
# inserts the string received
# (hopefully code) inside the
# user's program file as a 'sub'
sub _insert_code_in_file {
    my ($command_name, $code_text) = @_;

    my $sub =<<"EOSUB";
sub $command_name {
$code_text
}
EOSUB

    # tidy up the code, if Perl::Tidy is available
    eval "use Perl::Tidy ()";
    if (! $@) {
        my $new_code = '';
        Perl::Tidy::perltidy( argv => '', source => \$sub, destination => \$new_code );
        $sub = $new_code;
    }

#TODO: flock
#    eval {
#        use 'Fcntl qw(:flock)';
#    }
#    if ($@) {
#        carp 'Could not load file locking module';
#    }

    #TODO: I really should be using PPI
    #if the user has it installed...
    #or at least a decent parser
    open my $fh, '+<', $0
        or croak "error updating file $0: $!\n";

#    flock($fh, LOCK_EX) or carp "could not lock file $0: $!\n";

    my @file = <$fh>;
    _insert_code_into_array(\@file, $sub);

    # TODO: only change the file if
    # it's eval'd without errors
    seek ($fh, 0, 0) or croak "error seeking file $0: $!\n";
    print $fh @file or croak "error writing to file $0: $!\n";
    truncate($fh, tell($fh)) or croak "error truncating file $0: $!\n";

    close $fh;
}


sub _insert_code_into_array {
    my ($file_array_ref, $sub) = @_;
    my $changed = 0;

    $sub = "\n\n" . $sub . "\n\n";

    my $line_id = 0;
    while ( $file_array_ref->[$line_id] ) {

        # this is a very rudimentary parser. It assumes a simple
        # vanilla application as shown in the main example, and
        # tries to include the given subroutine just after the
        # App::Rad->run(); call.
        next unless $file_array_ref->[$line_id] =~ /App::Rad->run/;

        # now we add the sub (hopefully in the right place)
        splice (@{$file_array_ref}, $line_id + 1, 0, $sub);
        $changed = 1;
        last;
    }
    continue {
        $line_id++;
    }
    if ( not $changed ) {
        croak "error finding 'App::Rad->run' call. $0 does not seem a valid App::Rad application.\n";
    }
}


# deparses one-liner into a working subroutine code
sub _deparse {

    my $arg_ref = shift;

    # create array of perl command-line 
    # parameters passed to this one-liner
    my @perl_args = ();
    while ( $arg_ref->[0] =~ m/^-/o ) {
        push @perl_args, (shift @{$arg_ref});
    }

    #TODO: I don't know if "O" and
    # "B::Deparse" can actually run the same way as
    # a module as it does via -MO=Deparse.
    # and while I can't figure out how to use B::Deparse
    # to do exactly what it does via 'compile', I should
    # at least catch the stderr buffer from qx via 
    # IPC::Cmd's run(), but that's another TODO
    my $deparse = join ' ', @perl_args;
    my $code = $arg_ref->[0];
    my $body = qx{perl -MO=Deparse $deparse '$code'};
    return $body;
}


# tries to adjust a subroutine into
# App::Rad's API for commands
sub _sanitize {
    my $code = shift;

    # turns BEGIN variables into local() ones
    $code =~ s{(?:local\s*\(?\s*)?(\$\^I|\$/|\$\\)}
              {local ($1)}g;

    # and then we just strip any BEGIN blocks
    $code =~ s{BEGIN\s*\{\s*(.+)\s*\}\s*$}
              {$1}mg;

    my $codeprefix =<<'EOCODE';
my $c = shift;
# its probably safe to remove the line below
local(@ARGV) = @{$c->argv};

EOCODE
    $code = $codeprefix . $code;

    return $code;
}


# overrides our pre-defined control
# functions with any available
# user-defined ones
sub _register_functions {
    my $c = shift;
    my %subs = _get_main_subs();

    # replaces only if the function is
    # in 'default', 'pre_process' or 'post_process'
    foreach ( keys %{$c->{'_functions'}} ) {
        if ( defined $subs{$_} ) {
            $c->debug("overriding $_ with user-defined function.");
            $c->{'_functions'}->{$_} = $subs{$_};
        }
    }
}

# retrieves command line arguments
# to be executed by the main program
sub _get_input {
    my $c = shift;

    my $cmd = defined ($ARGV[0]) 
            ? shift @ARGV
            : ''
            ;

    @{$c->argv} = @ARGV;
    $c->{'cmd'} = $cmd;

    $c->debug('received command: ' . $c->{'cmd'});
    $c->debug('received parameters: ' . join (' ', @{$c->argv} ));

    $c->_tinygetopt();
#    return ($cmd, \@ARGV);
}

# stores arguments passed to a
# command via --param[=value] or -p
sub _tinygetopt {
    my $c = shift;

    foreach ( @{$c->argv} ) {

        # single option (could be grouped)
        if ( m/^\-([^\-\=]+)$/o) {
            my @args = split //, $1;
            foreach (@args) {
                $c->options->{$_} = '';
            }
        }
        # long option: --name or --name=value
        elsif (m/^\-\-([^\-\=]+)(?:\=(.+))?$/o) {
            $c->options->{$1} = $2 
                              ? $2 
                              : ''
                              ;
        }
    }
}


# removes given sub from the
# main program
sub _remove_code_from_file {
    my $sub = shift;

    #TODO: I really should be using PPI
    #if the user has it installed...
    open my $fh, '+<', $0
        or croak "error updating file $0: $!\n";

#    flock($fh, LOCK_EX) or carp "could not lock file $0: $!\n";

    my @file = <$fh>;
    my $ret = _remove_code_from_array(\@file, $sub);

    # TODO: only change the file if it's eval'd without errors
    seek ($fh, 0, 0) or croak "error seeking file $0: $!\n";
    print $fh @file or croak "error writing to file $0: $!\n";
    truncate($fh, tell($fh)) or croak "error truncating file $0: $!\n";

    close $fh;

    return $ret;
}

sub _remove_code_from_array {
    my $file_array_ref = shift;
    my $sub = shift;

    my $index = 0;
    my $open_braces = 0;
    my $close_braces = 0;
    my $sub_start = 0;
    while ( $file_array_ref->[$index] ) {
        if ($file_array_ref->[$index] =~ m/\s*sub\s+$sub(\s+|\s*\{)/) {
            $sub_start = $index;
        }
        if ($sub_start) {
            # in order to see where the sub ends, we'll
            # try to count the number of '{' against
            # the number of '}' available

            #TODO:I should use an actual LR parser or
            #something. This would be greatly enhanced
            #and much less error-prone, specially for
            #nested symbols in the same line.
            $open_braces++ while $file_array_ref->[$index] =~ m/\{/g;
            $close_braces++ while $file_array_ref->[$index] =~ m/\}/g;
            if ( $open_braces > 0 ) {
                if ( $close_braces > $open_braces ) {
                    croak "Error removing $sub: could not parse $0 correctly.";
                }
                elsif ( $open_braces == $close_braces ) {
                    # remove lines from array
                    splice (@{$file_array_ref}, $sub_start, ($index + 1 - $sub_start));
                    last;
                }
            }
        }
    }
    continue {
        $index++;
    }

    if ($sub_start == 0) {
        return "Error finding '$sub' command. Built-in?";
    }
    else {
        return "Command '$sub' successfuly removed.";
    }
}


#========================#
#     PUBLIC METHODS     #
#========================#

sub register_commands {
    my ($c, $options) = @_;
    if ($options) {
        croak '"register_commands" may receive only a hash reference'
            unless ref($options) eq 'HASH';
    }

    my %subs = _get_main_subs();

    foreach my $subname ( keys %subs ) {

        # we only add the sub to the commands
        # list if it's *not* a control function
        if ( not defined $c->{'_functions'}->{$subname} ) {

            if ( $options->{'ignore_prefix'} ) {  
                next if ( substr ($subname,
                                  0,
                                  length($options->{'ignore_prefix'})
                                 )
                          eq $options->{'ignore_prefix'}
                        );
            }
            elsif ( $options->{'ignore_suffix'} ) {
                next if ( substr ($subname, 
                                  length($subname) - length($options->{'ignore_suffix'}), 
                                  length($options->{'ignore_suffix'})
                                 )
                          eq $options->{'ignore_suffix'}
                        );
            }
            elsif ( $options->{'ignore_regexp'} ) {
                my $re = $options->{'ignore_regexp'};
                next if $subname =~ m/$re/;
            }

            $c->debug("registering $subname as a command.");
            $c->{'_commands'}->{$subname} = $subs{$subname};
        }
    }
}


sub register_command {
    my ($c, $command_name, $coderef) = @_;

    return undef
        unless ( (ref $coderef) eq 'CODE' );

    $c->{'_commands'}->{$command_name} = $coderef;
}


sub unregister_command {
    my ($c, $command_name) = @_;

    if ( $c->{'_commands'}->{$command_name} ) {
        delete $c->{'_commands'}->{$command_name};
    }
    else {
        return undef;
    }
}


sub create_command_name {
    my $id = 0;
    foreach (commands()) {
        if ( m/^cmd(\d+)$/ ) {
            $id = $1 if ($1 > $id);
        }
    }
    return 'cmd' . ($id + 1);
}


sub commands {
    my $c = shift;
    return ( keys %{$c->{'_commands'}} );
}


sub is_command {
    my ($c, $cmd) = @_;
    return (defined $c->{'_commands'}->{$cmd}
            ? 1
            : 0
           );
}


sub cmd {
    my $c = shift;
    return $c->{'cmd'};
}

sub command {
    return cmd(@_);
}


sub run {
    my $class = shift;
    my $c = {};
    bless $c, $class;

    $c->_init();

    # first we update the control functions
    # with any overriden value
    $c->_register_functions();

    # then we run the setup to register
    # some commands
    $c->{'_functions'}->{'setup'}->($c);

    # now we get the actual input from
    # the command line (someone using the app!)
    $c->_get_input();

    # run the specified command
    $c->execute();

    # that's it. Tear down everything and go home :)
    $c->{'_functions'}->{'teardown'}->($c);

    return 0;
}


# executes a given command, or
# the one in $c->{'cmd'} if none
# specified.
sub execute {
    my ($c, $cmd) = @_;

    # given command has precedence
    if ($cmd) {
        $c->{'cmd'} = $cmd;
    }
    else {
        $cmd = $c->{'cmd'};  # now $cmd always has the called cmd
    }

    $c->debug('calling pre_process function...');
    $c->{'_functions'}->{'pre_process'}->($c);

    # 2: actually run the command
    # (with the pre-processed arguments)
    $c->debug("executing '$cmd'...");
    if ($c->is_command($c->{'cmd'}) ) {
        $c->{'output'} = $c->{'_commands'}->{$cmd}->($c);
    }
    else {
        $c->debug("'" . $c->{'cmd'} . "' not a command. Falling to default.");
        $c->{'output'} = $c->{'_functions'}->{'default'}->($c);
    }

    # 3: post-process the result
    # from the command
    $c->debug('calling post_process function...');
    $c->{'_functions'}->{'post_process'}->($c);

    $c->debug('reseting output');
    $c->{'output'} = undef;
}

#TODO: sub shell { } - run operations 
#in a shell-like environment


sub argv {
    my $c = shift;
    return $c->{'ARGV'};
}

sub options {
    my $c = shift;
    return $c->{'_options'};
}

sub stash {
    my $c = shift;
    return $c->{'_stash'};
}    

sub getopt {
    my ($c, @options) = @_;

    # reset values from tinygetopt
    $c->{'_options'} = {};

    my $parser = new Getopt::Long::Parser;
    $parser->configure( qw(bundling) );

    return $parser->getoptions($c->{'_options'}, @options);
}

sub debug {
    my $c = shift;
    if ($c->{'debug'}) {
        print "[debug]   @_\n";
    }
}

# gets/sets the output (returned value)
# of a command, to be post processed
sub output {
    my ($c, @msg) = @_;
    if (@msg) {
        $c->{'output'} = join(' ', @msg);
    }
    else {
        return $c->{'output'};
    }
}


#=========================#
#     CONTROL FUNCTIONS   #
#=========================#

sub setup {
    my $c = shift;
    $c->register_commands();
}


sub pre_process {
}


sub post_process {
    my $c = shift;

    if ($c->output()) {
        print $c->output() . $/;
    }
}


sub default {
    my $c = shift;
    return $c->{'_commands'}->{'help'}->($c);
}


sub teardown {
}


#=========================#
#    BUILT-IN COMMANDS    #
#=========================#


# shows specific help commands
# TODO: context specific help, 
# such as "myapp.pl help command"
sub help {
    my $c = shift;
    my $string = "Usage: $0 command [arguments]\n\n"
               . "Available Commands:\n"
               ;

    foreach ( $c->commands() ) {
        $string .= "   $_\n";
    }

    return $string;
}


# includes a one-liner as a command.
# TODO: don't let the user include
# a control function!!!!
sub include {
    my $c = shift;

    my @args = @{$c->argv};

    if( @args < 3 ) {
        return "Sintax: $0 include [name] -perl_params 'code'.\n";
    }

    # figure out the name of
    # the command to insert.
    # Either the user chose it already
    # or we choose it for the user
    my $command_name = '';
    if ( $args[0] !~ m/^-/o ) {
        $command_name = shift @args;

        # don't let the user add a command
        # that already exists
        if ( $c->is_command($command_name) ) {
            return "Command '$command_name' already exists. Please remove it first with '$0 exclude $command_name";
        }
    }
    else {
        $command_name = $c->create_command_name();
    }
    $c->debug("including command '$command_name'...");

    my $code_text = _get_oneliner_code(\@args);

    _insert_code_in_file($command_name, $code_text);

    # turns code string into coderef so we
    # can register it (just in case the user
    # needs to run it right away)
    my $code_ref = sub { eval $code_text};
    $c->register_command($command_name, $code_ref);

    return; 
}

sub exclude {
    my $c = shift;
    if ( $c->argv->[0] ) {
        if ( $c->is_command( $c->argv->[0] ) ) {
            return _remove_code_from_file($c->argv->[0]);
        }
        else {
            return $c->argv->[0] . ' is not an available command';
        }
    }
    else {
        return "Sintax: $0 exclude command_name"
    }
}


}
42; # ...and thus ends thy module  ;)

__END__

=head1 NAME

App::Rad - Rapid (and easy!) creation of command line applications

=head1 VERSION

Version 0.04

=head1 SYNOPSIS

This is your smallest working application (let's call it I<myapp.pl>)

    use App::Rad;
    App::Rad->run();

That's it, your program already works and you can use it directly via the command line (try it!)

    [user@host]$ ./myapp.pl
    Usage: myapp.pl command [arguments]
    
    Available Commands:
        help

Next, start creating your own functions (e.g.) inside I<myapp.pl>:

    sub hello {
        return "Hello, World!";
    }

And now your simple command line program I<myapp.pl> has a 'hello' command!

   [user@host]$ myapp.pl hello
   Hello, World!

Of course, you probably want to create a more meaningful command, with arguments and options:

    # dice roller: 2d6, 1d10, etc...
    sub roll {
        my $c = shift;
        my $value = 0;

        if ( $c->argv->[0] =~ m/(\d+)d(\d+)/ ) {
            for (1..$1) {
                $value += int(rand ($2) + 1);
            }
        }
        return $value;
    }

There it is, a brand new 'roll' command! You can try on the command line:

   [user@host]$ myapp.pl roll 3d4
   5


=head1 WARNING

This module is very young, likely to change in strange ways and to have some bugs (please report if you find any!). I will try to keep the API stable, but even that is subject to change (let me know if you find anything annoying or have a wishlist). You have been warned!


=head1 WARNING II (MODULE NAME)

I'm still trying to figure out a nice name for this module, so it might change. Feel free to offer me any naming suggestions you might have :)


=head1 DESCRIPTION

App::Rad aims to be a simple yet powerful framework for developing your command-line applications. It can easily transform your Perl I<one-liners> into reusable subroutines than can be called directly by the user of your program.

It also tries to provide a handy interface for your common command-line tasks. B<If you have a feature request to easen out your tasks even more, please drop me an email or a RT feature request.>



=head1 BUILT-IN COMMANDS

This module comes with the following default commands. You are free to override them as you see fit.


=head2 help

Shows help information for your program. This built-in function displays the program name and all available commands (including the ones you included). If a user of our minimal I<myapp.pl> example typed the 'help' command, or no command at all, or any command that does not exist (as they'd fall into the 'default' control function which (by default) calls 'help'), this would be the output:

    [user@host]$ myapp.pl help
    Usage: myapp.pl command [arguments]
    
    Available Commands:
        hello
        help
        roll



=head1 OTHER BUILT IN COMMANDS (OPT-IN)

The 'include' and 'exclude' commands below let the user include and exclude commands to your program and, as this might be dangerous when the user is not yourself, you have to opt-in on them:

   use App::Rad qw(include);  # add the 'include' command
   use App::Rad qw(exclude);  # add the 'exclude' command

though you'll probably want to set them both:

   use App::Rad qw(include exclude);

=head2 include I<[command_name]> I<-perl_params> I<'your subroutine code'>

Includes the given subroutine into your program on-the-fly, just as you would writing it directly into your program.

Let's say you have your simple I<'myapp.pl'> program that uses App::Rad sitting on your system quietly. One day, perhaps during your sysadmin's tasks, you create a really amazing one-liner to solve a really hairy problem, and want to keep it for posterity (reusability is always a good thing!). 

For instance, to change a CSV file in place, adding a column on position #2 containing the line number, you might do something like this (this is merely illustrative, it's not actually the best way to do it):

    $ perl -i -paF, -le 'splice @F,1,0,$.; $_=join ",",@F' somesheet.csv

And you just found out that you might use this other times. What do you do? App::Rad to the rescue!

In the one-liner above, just switch I<'perl'> to I<'myapp.pl include SUBNAME'> and remove the trailing parameters (I<somesheet.csv>):

    $ myapp.pl include addcsvcol -i -paF, -le 'splice @F,1,0,$.; $_=join ",",@F'

That's it! Now myapp.pl has the 'addcsvcol' command (granted, not the best name) and you can call it directly whenever you want:

    $ myapp.pl addcsvcol somesheet.csv

App::Rad not only transforms and adjusts your one-liner so it can be used inside your program, but also automatically formats it with Perl::Tidy (if you have it). This is what the one-liner above would look like inside your program:

    sub addcsvcol {
        my $c = shift;
    
        # its probably safe to remove the line below
        local (@ARGV) = @{ $c->argv };
    
        local ($^I) = "";
        local ($/)  = "\n";
        local ($\)  = "\n";
      LINE: while ( defined( $_ = <ARGV> ) ) {
            chomp $_;
            our (@F) = split( /,/, $_, 0 );
            splice @F, 1, 0, $.;
            $_ = join( ',', @F );
        }
        continue {
            die "-p destination: $!\n" unless print $_;
        }
    }

With so many arguments (-i, -p, -a -F,, -l -e), this is about as bad as it gets. And still one might find this way easier to document and mantain than a crude one-liner stored in your ~/.bash_history or similar.

B<Note:> If you don't supply a name for your command, App::Rad will make one up for you (cmd1, cmd2, ...). But don't do that, as you'll have a hard time figuring out what that specific command does.

B<Another Note: App::Rad tries to adjust the command to its interface, but please keep in mind this module is still in its early stages so it's not guaranteed to work every time. *PLEASE* let me know via email or RT bug request if your one-liner was not correctly translated into an App::Rad command. Thanks!>


=head2 exclude I<command_name>

Removes the requested function from your program. Note that this will delete the actual code from your program, so be *extra* careful. It is strongly recommended that you do not use this command and either remove the subroutine yourself or add the function to your excluded list inside I<setup()>.

Note that built-in commands such as 'help' cannot be removed via I<exclude>. They have to be added to your excluded list inside I<setup()>.



=head1 ROLLING YOUR OWN COMMANDS

Creating a new command is as easy as writing any sub inside your program. Some names ("setup", "default", "pre_process", "post_process" and "teardown") are reserved for special purposes (see the I<Control Functions> section of this document). App::Rad provides a nice interface for reading command line input and writing formatted output:


=head2 The Controller

Every command (sub) you create receives the controller object "C<< $c >>" (sometimes referred as "C<< $self >>" in other projects) as an argument. The controller is the main interface to App::Rad and has several methods to easen your command manipulation and execution tasks.


=head2 Reading arguments

=head3 $c->argv

When someone types in a command, she may pass some arguments to it. Those arguments are stored in raw format inside the array reference C<< $c->argv >>. This way it's up to you to control how many arguments (if at all) you want to receive and/or use.

So, in order to manipulate and use any arguments, remember:

    sub my_command {
        my $c = shift;
    
        # now everything the user typed after the name of
        # your command is inside @{$c->argv} so you can
        # use $c->argv->[0], $c->argv->[1], and so on, to
        # get and even reset any parameters.
    }

=head3 $c->options

App::Rad lets you automatically retrieve any POSIX syntax command line options (I<getopt-style>) passed to your command via the $c->options method. This method returns a hash reference with keys as given parameters and values as, well, values. The 'options' method automatically supports two simple argument structures:

Extended (long) option. Translates C<< --parameter or --parameter=value >> into C<< $c->options->{parameter} >>

Single-letter option. Translates C<< -p >> into C<< $c->options->{p} >>.

Single-letter options can be nested together, so C<-abc> will be parsed into C<< $c->options->{a} >>, C<< $c->options->{b} >> and C<< $c->options{c} >>, while C<--abc> will be parsed into C<< $c->options->{abc} >>. So our example dice-rolling command can be written this way:

    sub roll {
        my $c = shift;

        my $value = 0;
        for ( 1..$c->options->{'times'} ) {
            $value += ( int(rand ($c->options->{'faces'}) + 1));
        }
        return $value;
    }

And now you can call your 'roll' command like:

    $ myapp.pl roll --faces=6 --times=2

Note that the App::Rad does not control which arguments can or cannot be passed: they are all parsed into C<< $c->options >> and it's up to you to use whichever you want. For a more advanced use and control, see the C<< $c->getopt >> method below.

=head3 $c->getopt (Advanced Getopt usage)

App::Rad is also smoothly integrated with Getopt::Long, so you can have even more flexibility and power while parsing your command's arguments, such as aliases and types. Call the C<< $c->getopt() >> method anytime inside your commands (or just once in your "pre_process" function to always have the same interface) passing a simple array with your options, and refer back to $c->options to see them. For instance: 

    sub roll {
        my $c = shift;

        $c->getopt( 'faces|f=i', 'times|t=i' )
            or $c->execute('usage') and return undef;

        # and now you have C<< $c->options->{'faces'} >> 
        # and C<< $c->options->{'times'} >> just like above.
    }

This becomes very handy for complex or feature-rich commands. Please refer to the Getopt::Long module for more usage examples.


=head2 Sharing Data: C<< $c->stash >>

The "stash" is a universal hash for storing data among your Commands:

    $c->stash->{foo} = 'bar';
    $c->stash->{herculoids} = [ qw(igoo tundro zok gloop gleep) ];
    $c->stash->{application} = { name => 'My Application' };

You can use it for more granularity and control over your program. For instance, you can email the output of a command if (and only if) something happened:

    sub command {
        my $c = shift;
        my $ret = do_something();

        if ( $ret =~ /critical error/ ) {
            $c->stash->{mail} = 1;
        }
        return $ret;
    }

    sub post_process {
        my $c = shift;

        if ( $c->stash->{mail} ) {
            # send email alert...
        }
        else {
            print $c->output . "\n";
        }
    }



=head2 Returning output

Once you're through, return whatever you want to give as output for your command:

    my $ret = "Here's the list: ";
    $ret .= join ', ', 1..5;
    return $ret;
    
    # this prints "Here's the list: 1, 2, 3, 4, 5"

App::Rad lets you post-process the returned value of every command, so refrain from printing to STDOUT directly whenever possible as it will give much more power to your programs. See the I<post_process()> control function further below in this document.


=head1 HELPER METHODS

App::Rad comes with several functions to help you manage your application easily. B<If you can think of any other useful command that is not here, please drop me a line or RT request>.


=head2 $c->execute( I<COMMAND_NAME> )

Runs the given command. If no command is given, runs the one stored in C<< $c->cmd >>. If the command does not exist, the 'default' command is ran instead. Each I<execute()> call also invokes pre_process and post_process, so you can easily manipulate income and outcome of every command.


=head2 $c->cmd

Returns a string containing the name of the command (that is, the first argument of your program), that will be called right after pre_process.


=head2 $c->command

Alias to C<< $c->cmd >>.


=head2 $c->commands()

Returns a list of available commands (I<functions>) inside your program


=head2 $c->is_command ( I<COMMAND_NAME> )

Returns 1 (true) if the given I<COMMAND_NAME> is available, 0 (false) otherwise.


=head2 $c->create_command_name()

Returns a valid name for a command (i.e. a name slot that's not been used by your program). This goes in the form of 'cmd1', 'cmd2', etc., so don't use unless you absolutely have to. App::Rad, for instance, uses this whenever you try to I<include> (see below) a new command but do not supply a name for it.


=head2 $c->register_command ( I<NAME>, I<CODEREF> )

Registers a coderef as a callable command. Note that you don't have to call this in order to register a sub inside your program as a command, run() will already do this for you - and if you don't want some subroutines to be issued as commands you can always use C<< $c->register_commands() >> (note the plural) inside setup(). This is just an interface to dinamically include commands in your programs. The function returns the command name in case of success, undef otherwise.


=head2 $c->register_commands ()

This method, usually called during setup(), tells App::Rad to register all subroutines available in the main program as valid commands. It may optionally receive a hashref as an argument, letting you choose which subroutines to add as commands. The following keys may be used:

=over 4

=item * C<< ignore_prefix >>: subroutine names starting with the given string won't be added as commands

=item * C<< ignore_suffix >>: subroutine names ending with the given string won't be added as commands

=item * C<< ignore_regexp >>: subroutine names matching the given regular expression (as a string) won't be added as commands

=back

For example:

    use App::Rad;
    App::Rad->run();

    sub setup { 
        my $c = shift; 
        $c->register_commands( { ignore_prefix => '_' } );
    }

    sub foo  {}  # will become a command
    sub bar  {}  # will become a command
    sub _baz {}  # will *NOT* become a command

This way you can easily segregate between commands and helper functions, making your code even more reusable without jeopardizing the command line interface.


=head2 $c->unregister_command ( I<NAME> )

Unregisters a given command name so it's not available anymore. Note that the subroutine will still be there to be called from inside your program - it just won't be accessible via command line.


=head2 $c->debug( I<MESSAGE> )

Will print the given message on screen only if the debug flag is enabled:

    use App::Rad  qw( debug );

=head2 run()

this is the main execution command for the application. That's the B<*ONLY*> thing your script needs to actively do. Leave all the rest to your subs.


=head1 CONTROL FUNCTIONS (to possibly override)

App::Rad implements some control functions which are expected to be overridden by implementing them in your program. They are as follows:

=head2 setup()

This function is responsible for setting up what your program can and cannot do, plus everything you need to set before actually running any command (connecting to a database or host, check and validate things, download a document, whatever). Note that, if you override setup(), you B<< *must* >> call C<< $c->register_commands() >> or at least C<< $c->register_command() >> so your subs are classified as valid commands (check $c->register_commands() above for more information).

Another interesting thing you can do with setup is to manipulate the command list. For instance, you may want to be able to use the C<include> and C<exclude> commands, but not let them available for all users. So instead of writing:

    use App::Rad qw(include exclude);
    App::Rad->run();

you can write something like this:

    use App::Rad;
    App::Rad->run();

    sub setup {
        my $c = shift;
        $c->register_commands();

        # EUID is 'root'
        if ( $> == 0 ) {
            $c->register_command('include', \&App::Rad::include);
            $c->register_command('exclude', \&App::Rad::exclude);
        }
    }

to get something like this:

    [user@host]$ myapp.pl help
    Usage: myapp.pl command [arguments]

    Available Commands:
       help

    [user@host]$ sudo myapp.pl help
    Usage: myapp.pl command [arguments]

    Available Commands:
       include
       help
       exclude



=head2 default()

If your application does not have the given command, it will fall in here. Default's default (grin) is just an alias for the help command.

    sub default {
        my $c = shift;

        # will fall here if the given
        # command isn't valid.
    }

You are free (and encouraged) to change the default behavior to whatever you want. This is rather useful for when your program will only do one thing, and as such it receives only parameters instead of command names. In those cases, use the "default()" sub as your main program's sub and parse the parameters with $c->argv and $c->getopt as you would in any other command.


=head2 teardown()

If implemented, this function is called automatically after your application runs. It can be used to clean up after your operations, removing temporary files, disconnecting a database connection established in the setup function, logging, sending data over a network, or even storing state information via Storable or whatever.


=head2 pre_process()

If implemented, this function is called automatically right before the actual wanted command is called. This way you have an optional pre-run hook, which permits functionality to be added, such as preventing some commands to be run from a specific uid (e.g. I<root>): 

    sub pre_process {
        my $c = shift;

        if ( $c->cmd eq 'some_command' and $> != 0 ) {
            $c->cmd = 'default'; # or some standard error message
        }
    }
    

=head2 post_process()

If implemented, this function is called automatically right after the requested function returned. It receives the Controller object right after a given command has been executed (and hopefully with some output returned), so you can manipulate it at will. In fact, the default "post_process" function is as goes:

    sub post_process {
        my $c = shift;

        if ( $c->output() ) {
            print $c->output() . "\n";
        }
    }

You can override this function to include a default header/footer for your programs (either a label or perhaps a "Content-type: " string), parse the output in any ways you see fit (CPAN is your friend, as usual), etc.



=head1 IMPORTANT NOTE ON PRINTING INSIDE YOUR COMMANDS

B<The post_process() function above is why your application should *NEVER* print to STDOUT>. Using I<print> (or I<say>, in 5.10) to send output to STDOUT is exclusively the domain of the post_process() function. Breaking this rule is a common source of errors. If you want your functions to be interactive (for instance) and print everything themselves, you should disable post-processing in setup(), or create an empty post_process function or make your functions return I<undef> (so I<post_process()> will only add a blank line to the output).


=head1 DIAGNOSTICS

If you see a '1' printed on the screen after a command is issued, it's probably because that command is returning a "true" value instead of an output string. If you don't want to return the command output for post processing(you'll loose some nice features, though) you can return undef or make post_process() empty.


=head1 CONFIGURATION AND ENVIRONMENT

App::Rad requires no configuration files or environment variables.


=head1 DEPENDENCIES

App::Rad depends only on 5.8 core modules (Carp for errors, Getopt::Long for "$c->getopt" and O/B::Deparse for the "include" command).

If you have Perl::Tidy installed, the "include" command will tidy up your code before inclusion.

The test suite depends on Test::More and File::Temp, both also core modules.


=head1 INCOMPATIBILITIES

None reported.


=head1 BUGS AND LIMITATIONS

Please report any bugs or feature requests to 
C<bug-app-easy at rt.cpan.org>, or through the web interface at 
L<http://rt.cpan.org/garu/ReportBug.html?Queue=App-Rad>.  I will be notified, and then you'll automatically be notified of progress on your bug as I make changes.


=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc App::Rad


You can also look for information at:

=over 4

=item * RT: CPAN's request tracker

L<http://rt.cpan.org/garu/Bugs.html?Dist=App-Rad>

=item * AnnoCPAN: Annotated CPAN documentation

L<http://annocpan.org/dist/App-Rad>

=item * CPAN Ratings

L<http://cpanratings.perl.org/d/App-Rad>

=item * Search CPAN

L<http://search.cpan.org/dist/App-Rad>

=back


=head1 TODO

This is a small list of features I plan to add in the near future (in no particular order). Feel free to contribute with your wishlist and comentaries!

=over 4

=item * Alias creation

=item * Shell-like environment

=item * $c->load_config_file( I<FILE> )

=item * Extension possibilities (plugins!)

=item * Loadable commands (in an external container file)

=item * Modularized commands (similar to App::Cmd::Commands ?)

=item * Output Templating

=item * Embedded help

=item * app-starter

=item * command inclusion by prefix, suffix and regexp (feature request by fco)

=item * command inclusion and exclusion also by attributes

=item * differentiate between no command ( default() ) and invalid command ( invalid()? ) handling

=back


=head1 AUTHOR

Breno G. de Oliveira, C<< <garu at cpan.org> >>


=head1 ACKNOWLEDGEMENTS

This module was inspired by Kenichi Ishigaki's presentation I<"Web is not the only one that requires frameworks"> during YAPC::Asia::2008 and the modules it exposed (mainly App::Cmd and App::CLI).

Also, many thanks to CGI::App(now Titanium)'s Mark Stosberg and all the Catalyst developers, as some of App::Rad's functionality was taken from those (web) frameworks.


=head1 LICENSE AND COPYRIGHT

Copyright 2008 Breno G. de Oliveira C<< <garu at cpan.org> >>. All rights reserved.

This module is free software; you can redistribute it and/or modify it
under the same terms as Perl itself. See L<perlartistic>.



=head1 DISCLAIMER OF WARRANTY

BECAUSE THIS SOFTWARE IS LICENSED FREE OF CHARGE, THERE IS NO WARRANTY
FOR THE SOFTWARE, TO THE EXTENT PERMITTED BY APPLICABLE LAW. EXCEPT WHEN
OTHERWISE STATED IN WRITING THE COPYRIGHT HOLDERS AND/OR OTHER PARTIES
PROVIDE THE SOFTWARE "AS IS" WITHOUT WARRANTY OF ANY KIND, EITHER
EXPRESSED OR IMPLIED, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE. THE
ENTIRE RISK AS TO THE QUALITY AND PERFORMANCE OF THE SOFTWARE IS WITH
YOU. SHOULD THE SOFTWARE PROVE DEFECTIVE, YOU ASSUME THE COST OF ALL
NECESSARY SERVICING, REPAIR, OR CORRECTION.

IN NO EVENT UNLESS REQUIRED BY APPLICABLE LAW OR AGREED TO IN WRITING
WILL ANY COPYRIGHT HOLDER, OR ANY OTHER PARTY WHO MAY MODIFY AND/OR
REDISTRIBUTE THE SOFTWARE AS PERMITTED BY THE ABOVE LICENCE, BE
LIABLE TO YOU FOR DAMAGES, INCLUDING ANY GENERAL, SPECIAL, INCIDENTAL,
OR CONSEQUENTIAL DAMAGES ARISING OUT OF THE USE OR INABILITY TO USE
THE SOFTWARE (INCLUDING BUT NOT LIMITED TO LOSS OF DATA OR DATA BEING
RENDERED INACCURATE OR LOSSES SUSTAINED BY YOU OR THIRD PARTIES OR A
FAILURE OF THE SOFTWARE TO OPERATE WITH ANY OTHER SOFTWARE), EVEN IF
SUCH HOLDER OR OTHER PARTY HAS BEEN ADVISED OF THE POSSIBILITY OF
SUCH DAMAGES.
