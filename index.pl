#!/usr/bin/perl

# https://perl.com/pub/2012/04/perlunicook-standard-preamble.html
use utf8;      # so literals and identifiers can be in UTF-8
use v5.12;     # or later to get "unicode_strings" feature
use strict;    # quote strings, declare variables
use warnings;  # on by default
use warnings  qw(FATAL utf8);    # fatalize encoding glitches
use open      qw(:std :utf8);    # undeclared streams in UTF-8
use charnames qw(:full :short);  # unneeded in v5.16

# Other stuff.
use File::Spec;

our $AUTHOR='zrajm <zrajm@zrajm.org>';
our $VERSION='0.0.5';                          # https://semver.org/
our $VERSION_DATE='1 October 2025';
our $CREATED_DATE='10 August 2025'; # never change this!
our $PROGRAM = (File::Spec->splitpath(decode(__FILE__)))[2];
our $USAGE = <<"USAGE_END";
Usage: $PROGRAM [OPTION]
Build Markdown scented HTML 'index.html' from part-sources.

Will replace everything between HTML comments '<!--START-TABLE-->' and
'<!--END-TABLE-->' with a generated markdown table, and everything between
'<!--START-BODY-->' and '<!--END-BODY-->' with the text body. (The HTML
comments themselves are preserved, so this program may be run on its own
output.)

Options:
  -h, --help     Display this help and exit
  -V, --version  Output version information and exit

USAGE_END

use Data::Dumper;

###############################################################################
# Functions
{
    use Encode ();
    state sub OPT() { Encode::FB_CROAK | Encode::LEAVE_SRC }
    sub encode { eval { Encode::encode('UTF-8', shift // $_, OPT) } }
    sub decode { eval { Encode::decode('UTF-8', shift // $_, OPT) } }
}

sub help {
    print $USAGE;
    exit 0;
}
sub version {
    my ($years)    = $CREATED_DATE =~ m#(\d{4})#;
    my ($end_year) = $VERSION_DATE =~ m#(\d{4})#;
    $years .= "-$end_year" unless $years eq $end_year;
    say "$PROGRAM $VERSION ($VERSION_DATE)\n",
        "Copyright (C) $years $AUTHOR\n",
        "License GPLv2: GNU GPL version 2 <https://gnu.org/licenses/gpl-2.0.html>.\n",
        "This is free software: you are free to change and redistribute it.";
    exit 0;
}

# read file, return whole thing as a string
sub read_file {
    my ($file) = @_;
    open(my $in, "<:utf8", $file)
        or die "Failed to open file '$file' for reading: $!\n";
    local $/ = undef;
    return <$in>;
}

sub write_file {
    my ($file, $data) = @_;
    open(my $out, ">:utf8", $file)
        or die "Failed to open file '$file' for writing: $!\n";
    print $out $data;
    close($out)
        or die "Failed to close file after writing: $!\n"
}

# get max value in array
sub max {
    my ($max, @vars) = @_;
    for (@vars) {
        $max = $_ if $_ > $max;
    }
    return $max;
}

# trim whitespace
sub trim {
    my $s = shift;
    $s =~ s/^\s+|\s+$//g;
    return $s;
}

# Complete country list here:
# https://gist.github.com/selimata/75b5301b132bd541fe31e49cc38f61dc
sub flag {
    my ($txt) = @_;
    my %flag = (
        'Australia'     => '🇦🇺',
        'Belarus'       => '🇧🇾',
        'Belgium'       => '🇧🇪',
        'Brazil'        => '🇧🇷',
        'Colombia'      => '🇨🇴',
        'Denmark'       => '🇩🇰',
        'France'        => '🇫🇷',
        'Germany'       => '🇩🇪',
        'Great Britain' => '🇬🇧',
        'Italy'         => '🇮🇹',
        'Netherlands'   => '🇳🇱',
        'Russia'        => '🇷🇺',
        'Sweden'        => '🇸🇪',
        'United States' => '🇺🇸',
    );
    return $flag{$txt};
}

sub xtract_info {
    local ($_) = @_;
    # Key: One word followed by ':'.
    # Value: May continue across multiple lines if indented.
    my @x = m/^(?:\w+):\h*.*(?:\n\h+.+)*/gmx;
    return map {
        my ($key, $value) = m/^(\w+): *(.*)/s;
        $value =~ s#\n\h+# #g;                 # strip newline & indentation
        (lc $key, $value);
    } @x;
}

sub generate_table {
    my ($columns, $macro, %text) = @_;
    my @column_head = split(/ +/, $columns);
    my @column_name = map {
        local $_ = $_;
        s#<[^<>]*>##g;         # strip HTML
        lc $_;                 # downcase
    } @column_head;
    my @table = (
        [@column_head],
        map {
            my $file = $_;
            local $_ = $text{$_};

            #print("==> $file <==\n");
            my %x = xtract_info($_);

            say STDERR "No 'title' in file '$file'" unless $x{title};
            !$x{title} ? () : [map {
                my ($key, $value) = ($_, $x{$_} // do {
                    #say STDERR "No '$_' in file '$file'";
                    ''
                });
                $macro->{$key}
                    ? $macro->{$key}->($value, %x)
                    : $value;
            } @column_name];

        } sort(keys %text)
    );

    # Get width of each column.
    my @width = map {
        my $i = $_;
        max(map { length($_->[$i] // '') } @table);
    } (0..$#{$table[0]});

    # Printf template
    my $tmpl = join('', map { "| %-${_}s " } @width) . "|\n";

    # Insert |---| row in table
    splice(@table, 1, 0, [map { '-' x $_ } @width]);

    return join('', map { sprintf $tmpl, @$_ } @table);
}

sub generate_body {
    my (%text) = @_;
    return join '', map {
        my $body = $text{$_};
        my %meta = (
            xtract_info($body),
            id => do {                         # 'id' from filename
                my ($id) = m#\d{4}-(.*)\.txt$#;
                "#$id";
            });

        for ($body) {
            # Strip trailing '<--[eof]-->' any trailing 'pdf/*' lines.
            s{ ^ \n* (.*?) \n\n }{
                local $_ = $1;
                s#^:.*\n##gm;           # 'comments' (=header without name)
                s#^(\w+):#\n**$1:**#gm; # boldify header names
                "<details class=\"hanging summary\"><summary>\n$_\n\n</summary></details>\n\n";
            }sex;
            # Strip trailing '<--[eof]-->' any trailing 'pdf/*' lines.
            s#\n*\Q<!--[eof]-->\E\n*((?:pdf/.*)\n+)*\z##;
        }

        # Insert heading & chapter text.
        !$meta{title} ? '' : do {
            my ($title, $year) = @meta{qw/title year/};
            s#\h*\(.*?\)##g for $title, $year;
            <<~END_HEADING

            [$title]: $meta{id}
            ## [$meta{id}] $year: $title

            $body

            END_HEADING
        };
    } sort keys %text;
}

###############################################################################

my %macro = (
    year => sub {
        local $_ = shift;
        s#\h*\(.*?\)##g;
        return $_;
    },
    country => sub {
        local $_ = shift;
        s#\Q(?)#?#g;
        s#\h*\(.*?\)##g;
        return join(' ', map {
            $_ = trim($_);
            s#[^?A-Za-z ]+##g;
            s{ [A-Za-z ]+ }{ flag($&) // '??' }ex;
            $_;
        } split(/, */, $_));
    },
    creator => sub {
        local $_ = join '; ', map {
            s#\Q(?)#?#g;
            s#\h*\(.*?\)##g;
            s#,[^?]*(\??).*# $1 ? '?' : '' #e;
            $_;
        } split(/;\h*/, shift);
        s#;.*;.*# et al.#;
        return $_;
    },
    status => sub {
        my ($value, %values) = @_;
        my $creator = $values{creator} // '';
        my @status = map {
            my $x = quotemeta($_);
            $creator =~ m/\((${x}\??)\)/i ? do {
                (my $x = $1) =~ s#\bhard of hearing\b#HoH#g;
                $x;
            } : ();
        } ('hard of hearing', qw/hearing deaf ?/);
        # 'hearing', 'deaf', 'hearing & deaf' or '?'
        return @status ? join(' & ', @status) : '?';
    },
    graphemes => sub {
        local $_ = shift;
        s#\h*\(.*?\)##g;
        $_;
    },
    language => sub {
        local $_ = shift;
        s#\Q(?)#?#g;
        s#\h*\(.*?\)##g;
        return $_;
    },
    latin => sub {
        local $_ = shift;
        s#[\x00-\x3e\x40-\xff]##g;
        return $_;
    },
    title => sub {
        chomp(local $_ = shift);
        my $disputed = '';
        s{ \([^()]*\) }{
            if ($& eq '(?)') { $disputed = 1 }
            '';
        }gex;
        '[' . trim($_) . ']' . ($disputed && ' (?)');
    },
);

###############################################################################
# Main

local %SIG = (
    __WARN__ => sub { warn("$PROGRAM: @_") },
    __DIE__  => sub {
        die @_ if $^S;                         # abort if called inside eval
        my $more = (my $msg = "@_") =~ s/\.$//; # ending in '.' = extra help
        die "$PROGRAM: $msg",
            $more && "Try '$PROGRAM --help' for more information.\n";
    },
);

# Parse arguments (removing options).
@ARGV = do {
    @ARGV = map { decode } @ARGV;
    my @arg;
    while (@ARGV) {
        local $_ = shift;
        /^    --               $/x and push(@arg, @ARGV), last;
        /^(-h|--help)          $/x and help();
        /^(-V|--version)       $/x and version();
        /^-                     /x and die "Unrecognized option '$_'.\n";
        push(@arg, $_);
    }
    @arg;
};

# Read arguments
if (@ARGV != 0) { die "Bad number of args.\n" }
(my $file = __FILE__) =~ s#\.pl$#.html#;

# Read all 'YEAR-SYSTEM.txt' files.
my %file = map { $_ => read_file($_) // '' } sort <[0-9][0-9][0-9][0-9]*.txt>;

my $text = read_file($file);
my $org_text = $text;
for ($text) {
    s{(?<=\Q<!-- START-TABLE -->\E).*?(?=\Q<!-- END-TABLE -->\E)}{
        "\n" . generate_table(
            'Year Title <p>Latin <p>Graphemes <p>Language <p>Country Creator Status',
            \%macro, %file);
    }sme;
    s{(?<=\Q<!-- START-BODY -->\E).*?(?=\Q<!-- END-BODY -->\E)}{
        "\n" . generate_body(%file);
    }sme;
}

if ($text ne $org_text) {
    $text =~ s{(^Updated:)\s+(.*)\n}{ "$1 " . `date --iso=minutes` }me;

    # Atomic file update. Write to tempfile, then rename to overwrite original.
    # (Also save original as '.bak' file.)
    write_file("$file.tmp", $text) and do {
        my $bak = "$file.bak";
        my $tmp = "$file.tmp";
        if (-f $bak) {
            unlink("$bak")    or die "Can't remove previous '$bak': $!";
        }
        link($file, "$bak")   or die "Can't link '$file' -> '$bak': $!\n";
        rename("$tmp", $file) or die "Can't rename '$tmp' -> '$file': $!\n";
    };
    say STDERR "File '$file' updated";
} else {
    say STDERR "File '$file' unchanged";
}

#[eof]
