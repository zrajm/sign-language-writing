#!/usr/bin/perl

# https://perl.com/pub/2012/04/perlunicook-standard-preamble.html
use utf8;      # so literals and identifiers can be in UTF-8
use v5.12;     # or later to get "unicode_strings" feature
use strict;    # quote strings, declare variables
use warnings;  # on by default
use warnings  qw(FATAL utf8);    # fatalize encoding glitches
use open      qw(:std :utf8);    # undeclared streams in UTF-8
use charnames qw(:full :short);  # unneeded in v5.16

use File::Spec;

our $AUTHOR='zrajm <zrajm@zrajm.org>';
our $VERSION='0.0.2';                          # https://semver.org/
our $VERSION_DATE='12 August 2025';
our $CREATED_DATE='10 August 2025'; # never change this!
our $PROGRAM = (File::Spec->splitpath(decode(__FILE__)))[2];
our $USAGE = <<"USAGE_END";
Usage: $PROGRAM [OPTION]... FILE
Rebuild FILE (containing markdown source) from part-sources.

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
        'Belgium'       => '🇧🇪',
        'Brazil'        => '🇧🇷',
        'Colombia'      => '🇨🇴',
        'Denmark'       => '🇩🇰',
        'France'        => '🇫🇷',
        'Germany'       => '🇩🇪',
        'Great Britain' => '🇬🇧',
        'Italy'         => '🇮🇹',
        'Netherlands'   => '🇳🇱',
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
    my ($fields, $macro, %text) = @_;
    my @column_head = split(/ +/, $fields);
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
                    say STDERR "No '$_' in file '$file'";
                    ''
                });
                $macro->{$key} ? $macro->{$key}->($value) : $value;
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
                (my $a = $1) =~ s#^(\w+):#\n**$1:**#gm;
                "<details class=\"hanging summary\"><summary>\n$a\n\n</summary></details>\n\n";
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
        s#\(.*?\)##g;
        return join(' ', map {
            $_ = trim($_);
            s#[^?A-Za-z ]+##g;
            s{ [A-Za-z ]+ }{ flag($&) // '??' }ex;
            $_;
        } split(/, */, $_));
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

# Read arguments
if (@ARGV != 1) { die "$0: Bad number of args\nUsage: $0 FILE\n" }
my ($file) = @ARGV;

# Read all 'YEAR-SYSTEM.txt' files.
my %file = map { $_ => read_file($_) // '' } sort <[0-9][0-9][0-9][0-9]*.txt>;

my $text = read_file($file);
for ($text) {
    s{(?<=\Q<!-- START-TABLE -->\E).*?(?=\Q<!-- END-TABLE -->\E)}{
        "\n" . generate_table(
            'Year Title <p>Latin <p>Language <p>Country Creator',
            \%macro, %file);
    }sme;
    s{(?<=\Q<!-- START-BODY -->\E).*?(?=\Q<!-- END-BODY -->\E)}{
        "\n" . generate_body(%file);
    }sme;
}
print $text;

__END__
use File::Spec;
use Algorithm::Diff;

END { close(STDOUT) or die "Cannot close STDOUT: $!\n" }

our $AUTHOR='zrajm <zrajm@zrajm.org>';
our $VERSION='0.4.1';                          # https://semver.org/
our $VERSION_DATE='2 August 2025';
our $CREATED_DATE='28 October 2024'; # never change this!
our $PROGRAM = (File::Spec->splitpath(decode(__FILE__)))[2];
our $USAGE = <<"USAGE_END";
Usage: $PROGRAM [OPTION]... FILE1 FILE2
Compare FILE(s) and hilite changes.

Options:
      --command=CMD  Use CMD as a diff command (default: 'diff')
  -h, --help         Display this help, or COMMAND help, and exit
      --help-git     Display info on how to configure Git to use Prosediff
      --pager=CMD    Use CMD as pager (default: 'less -FRSX')
  -V, --version      Output version information and exit
      +STR           Pass `+STR` as argument to the pager (usually 'less')
                     (e.g. use +'/^[<>]' to search for added/removed lines)

Prosediff runs either in wrapper, or in filter mode. In both cases the output
is colorized and passed on to a pager. Most commonly, Prosediff is run in the
same as `diff` on the command line---in this case all arguments are passed on
to `diff` before Prosediff colorize the output (wrapper mode). Alternatively,
Prosediff can be run with no arguments with the output of a `diff` command
piped into it (filter mode).

Prosediff uses a two-level coloring scheme. Line-level hilites (a dark red or
green background) is used to indicate any line difference (including changes in
whitespace), while word-level hilites (a slightly brighter background color)
completely ignores whitespace (including line breaks and changes in word
wrapping or indentation), but hilite changed words/numbers and punctuation
characters. (Thus, if you see a hunk without word-level hilites, the only
difference is the spacing.)

NOTE: When using --command, make sure that your diff command produces output in
either the 'unified diff' (patch) or 'normal diff' format. (If you are using
Delta, --command='delta --color-only' is your friend, since the fancy output
formats of Delta are not understood by Prosediff.)
USAGE_END

# Other diff commands
# ===================
#
# Traditional diffs (probably available in your distro):
#
#   * `colordiff`
#   * `wdiff`
#
# Moar new ones:
#
#   * `delta`
#     (Debian package `git-delta`)
#   * `diff-so-fancy`
#     [https://github.com/so-fancy/diff-so-fancy]
#   * `difftastic`
#     [https://difftastic.wilfred.me.uk/]
#

###############################################################################
# History
#
# [2024-10-28, 22:27-01:39] & [2024-10-29, 06:44-10:07] v0.1.0 -- Basic
# functionality, diffing and hiliting works. Always zero lines of context. Only
# options supported is --help and --version (and their short forms). Missing
# file timestamps in output.
#
# [2024-10-30, 04:58-05:45] v0.2.0 - Now output proper timestamps for files.
#
# [2024-10-30, 06:17-11:30] v0.3.0 - Git's 'interactive diffFilter' apparently
# requires that the program parses and hilite diff output from Git (in a `diff
# -u` format) rather than do any diffing by itself). This version implements
# reading diff input and syntax hilite of that.
#
# [2024-10-30, 19:57-20:02] (code) & [2024-10-31 08:23-08:48] (documenting)
# v0.3.1 - Hunk matching now requires the more specific '^@@ -N[,N] +N[,N] @@'
# (instead of only '^@@'). Prosediff only messes with those lines that start
# with '-' and '+' and are found within @@...@@ lines, being a little more
# specific lessens the likelihood of false positives if non patches are fed
# through Prosediff (which is handy when it's being used as a text filter).
#
# [2024-10-31 08:39-09:12] v0.3.2 - Rudimentary implementation of always using
# external `diff -u0` command.
#
# [2024-10-31 11:34-13:07] v0.3.3 - Now pass all Diff command when invoked in
# wrapper mode. Wrapper mode requires that no args are given. Wrapper mode also
# supports the '-' argument (to pass in one of the files through STDIN).
# However, the default output (when `diff` is invoked without the `-u` option)
# will not be colorized, since Prosediff currently only hilites patches (which
# uses '-' and '+' to indicate changes, rather Diff's default '<' and '>').
#
# [2024-10-31 13:10-12:11] v0.3.4 - Slightly darker word-level hilite colors.
#
# [2024-10-31 13:14-14:13] & [15:42-17:16] v0.3.5 - Support normal diff output.
# The format where '>' and '<' is used to indicate new lines (instead of '-'
# and '+'). Now also reads and processes input incrementally. Instead of first
# reading all the input and then go on to processing it, each hunk is read and
# processed one after another.
#
# [2024-11-01, 09:27-10:17] v0.3.6 - Bugfix: Added missing '$' which prevented
# patch diffs containing ANSI codes from being parsed. (Yikes! That was hard to
# find!)
#
# [2024-11-01, 10:20-10:21] v0.3.7 - Simplified regex for matching ANSI codes.
#
# [2024-11-02 06:54-07:01] v0.3.8 - Minor refactoring of ReadDiff::read().
#
# [2024-11-03 08:07-12:46] v0.3.9 - Handle multi-file diffs (that is, the kind
# of output one gets from `git diff`). Only diff lines (not diff headers and
# metadata lines) are processed during hiliting, all other lines are retained
# as-is (keeping any previously existing hiliting).
#
# [2024-11-03, 13:03-13:37] v0.3.10 - Added --help-git option.
#
# [2024-11-03, 13:45-14:24] v0.3.11 - Added and deleted lines are now hilited
# with bright colors, only changed lines have dark background, and brighter
# background for individual added/deleted words.
#
# [2024-11-03, 14:26-15:33] v0.3.12 - Exit status now reflect Diff's exit
# status when run in wrapper mode.
#
# [2024-11-03, 15:50-16:54] v0.3.13 - Added --command=CMD option for selecting
# a different underlying Diff command.
#
# [2024-11-03, 21:39-21:49] v0.3.14 - Documented how to set Git settings with
# `git config`.
#
# [2024-11-03 21:52-23:20] v0.3.15 - Refactored colorize_diff().
#
# [2024-11-04 01:15-02:37] v0.3.17 - Added pager support. (The pager will be
# automatically disabled if STDOUT is not on a terminal.) Also, now both the
# diff and the pager commands may be specified with arguments.
#
# [2024-11-04 12:27-15:41] v0.3.18 - Optimized ANSI color code output. Now
# there should be far fewer color sequences emitted.
#
# [2024-11-05 14:09-01:27] v0.3.19 - Gracefully handle ANSI styled input.
# Prosediff will now, given ANSI style input(s) (e.g. syntax hilited source
# code), produce nicely looking hilites (while preserving the inputted ANSI
# styles). For this to work, the input sources must be hilited in the same way
# (only the word-level hilites ignore the ANSI styles). This works by
# normalizing ANSI markup in the input and stripping off background colors.
# Prosediff then adds its own background colors in to hilite the diffs.
#
# With this change you can produce a diff from syntax hilited source using
# `prosediff <(bat -pf FILE1) <(bat -pf FILE2)`, or use Prosediff enhance the
# output of Colordiff (e.g. `colordiff FILE1 FILE2|prosediff`).
#
# [2024-11-15 14:46-15:22] v0.3.21 - Now use newer version of normalise_ansi()
# (from my 'minify-ansi' program) which supports for colon as an ANSI argument
# delimiter. This means that a sequence command and its arguments may now be
# separated from each other using ':', as well as the older ';'. (If there are
# multiple commands in a sequence, then these are always separated from each
# other using ';'.)
#
# The use of two separators (instead of just ';') results in better in more
# graceful fails if non-existing commands are invoked. It also allows the
# extended underline sequence 'ESC[4:#m' (for setting underline style, used for
# double and wavy underlines).
#
# E.g. if a user tries to set the background using 'ESC[48;2;127;127;127m' --
# on a terminal which doesn't support true color this will result in dim mode
# being set (since '48' is ignored, and the dim mode sequence '2' in used
# instead, while the following '127' (not being a valid command), is ignored.
# If the sequence instead had its arguments separated by colon
# 'ESC[48:2:127:127:127m', then the terminal knows to skip the entire ANSI
# command, and dim more is not enabled.
#
#     + 'ESC[58;2;<r>;<g>;<b>m      underline color (r/g/b = 0-255)
#     + 'ESC[58;5;<n>m'             underline color (n = 0-255)
#     + 'ESC[59m'                   reset underline color
#
#     + 'ESC[4:0m'  underline off    [wezfurlong.org/wezterm/escape-sequences.html]
#     + 'ESC[4:1m'  underline on     (these must use ':' not ';'!)
#     + 'ESC[4:2m'  underline double
#     + 'ESC[4:3m'  underline curly
#     + 'ESC[4:4m'  underline dotted
#     + 'ESC[4:5m'  underline dashed
#
#     + 'ESC[53m'                   overline (on/off)
#     + 'ESC[55m'                   reset overline
#
#     + 'ESC[59m'                   superscript
#     + 'ESC[59m'                   subscript
#     + 'ESC[59m'                   reset superscript/subscript
#
# [2024-11-15 15:23-15:25] v0.3.22 - Added functions for RGB cube 5 colors.
#
# [2025-01-09 11:07-11:15] v0.3.23 - BUGFIX: Don't throw warning on empty input.
#
# [2025-01-09 11:33-11:37] v0.3.24 - BUGFIX: Decode arguments before (and not
# inside) command line processing loop, that way arguments may be put back into
# @ARGV without them being decoded twice.
#
# [2025-04-24 15:14-15:44] v0.4.0 - Added +STR option.
#
# [2025-04-24 20:10] v0.4.1 - Fixed --help info on +STR option.
#
# [2025-08-02 15:48-16:55] v0.4.2 - rephrased help info
#

###############################################################################
# TODO (in approximate order of priority)
#
#   * New ANSI codes to support. Note that extended 'ESC[4:<n>m' underline
#     sequences REQUIRES colon as delimiter (never semicolon) since it is
#     otherwise indistinguishable multiple ANSI commands given after each
#     other. This means that Prosediff needs be able recognize two different
#     reset sequences for underline (new 'ESC[4:0m' AND old 'ESC[24m').
#
#     + 'ESC[48;0m'                 implementation defined (for foreground only)
#     + 'ESC[48;1m'                 transparent (what's the reset for this?)
#     + 'ESC[48;3;<c>;<m>;<y>m'     CMY colors (c/m/y = 0-255(?))
#     + 'ESC[48;4;<c>;<m>;<y>;<k>m' CMYK colors (c/m/y/k = 0-255(?))
#
#     [https://en.wikipedia.org/wiki/ANSI_escape_code#3-bit_and_4-bit]
#     [https://learn.microsoft.com/en-us/windows/console/console-virtual-terminal-sequences]
#     [https://gist.github.com/fnky/458719343aabd01cfb17a3a4f7296797]
#
#   * Config file support.
#
#   * Allow specification of colors.
#
#   * Capture and rewrite Diff's output on STDERR. When there's an error, the
#     error messages shouldn't refer to `diff`, but rather `prosediff`.
#
#   * Option for hiding hunks in which there's only been a change in
#     whitespace. (This is useful when one wants to quickly gauge *actual*
#     changes made to a file.) Currently hunks with whitespace-only changes are
#     shown (but with only line hilites, no word hilites). This option would
#     suppress whitespace-only hunks from being output altogether. The inverse
#     option (that is, show *only* hunks with whitespace-only changes) would
#     probably also be useful.
#
#   * Hilite whitespace at end of line.
#
#   * Color control. (Just like `grep`, `ls` etc.). Option name
#     `--color[=WHEN]`, `--colour[=WHEN]`, Where WHEN is documented as `auto`
#     (default), `always` (default if `--color` option is given without arg),
#     or `never` (but values `if-tty`/`tty`, `force`/`yes` and `none`/`no` are
#     also allowed). Short opts `-c` for `--color=always` and `-C` for
#     `--color=never`.
#
#   * Add syntax hilite? This should be an option to feed the original
#     (unhilited) hunks through a text filter (e.g. `bat`) before Prosediff
#     adds it's own background markup. This would require that the hiliter only
#     affect style and foreground color (not background), any background markup
#     produced by the filter should be ignored or stripped by Prosediff. (Would
#     this work? What would happen to syntactic constructs broken over multiple
#     lines? Will they be hilited okayish enough for this to be useful?)
#
#     Use command `bat --theme=ansi --style=plain FILE` to perform syntax
#     hilite.
#
#   * Option to break hunks into as small pieces as possible. Edits within
#     lines should be put into a one-line hunk, even when directly adjacent to
#     another edited line. That is, what is now shown as:
#
#         -aaa bbb
#         -ccc ddd
#         +aaa bbb ADDED
#         +ddd
#
#     Should instead be shown as:
#
#         -aaa bbb
#         +aaa bbb ADDED
#         -ccc ddd
#         +ddd
#
#     However, if the edits cross a linebreak (for example, lines are
#     rewrapped), the hunk should remain large enough to capture this.
#
#         -aaa bbb ccc (DDDDDD)
#         -eee fff ggg
#         +aaa bbb ccc
#         +(DDDDDD) eee fff ggg
#
#    Option name? Preferably something relative intuitive with a good, uncommon
#    shortopt name. Maybe `-b`/`--break`?. -- Option names `--split`,
#    `--interlace`, `--interleave`, `--uncluster` are also good-ish, but `-s`
#    (very common) or `-i` (same grep's `--ignore-case`) and `-u` (same as
#    diff's `--unified`) are less good shortopt names.
#
# * Interactive patch mode? (Honestly, this should probably be a separate
#   program.) This would display a diff in interactive mode, allowing you to
#   select (and deselect) hunks interactively (in a viewer similar to Less).
#
#   Upon exiting this should write a patchfile (and output the command needed
#   to apply that patch as a commit in Git onto standard output). One should
#   also be able to provide one (or more?) patchfile(s) like this as 3rd (and
#   4th and 5th etc.) arguments to resume working on a patch.
#
#   Editing capabilities should include, being able to navigate between the
#   hunks, select a hunk, or specific change(s) inside of a hunk (sub-hunk
#   selection), searching for a specific string add (a) either automatically
#   select all matching hunks or (b) jump between matching hunks for manual
#   selection. For search one should also be able to specify 'search anywhere'
#   or 'search changes only`. I think arrow/up down to jump between hunks
#   should work pretty good, and possibly use left/right to move selection
#   between hunks? (That, or `a1` for 'add to hunk one'.)
#
#   Being able to work with multiple patches (with different color hilites)
#   would be cool, cause then one could, for example, immediately assign all
#   matching hunks to a new (possibly temporary) patch, navigate through that
#   patch to inspect each hunk and move the result to a different patch, or
#   unselect it.
#
#   The search should also have an option to work non-interactively. For
#   example (using a Less like 'keyboard input' option '+'):
#
#       prosediff +/newVar +a1 +q oldfile.txt newfile.txt patch.diff
#
#   This would diff `oldfile.txt` and `newfile.txt`, search the hunks for
#   'newVar', add them to patchfile 1 (by executing keyboard command 'a1') then
#   quit (thereby updating 'patch.diff'). The patchfile `patch.diff` is created
#   if it didn't already exist, but if it did exist any previously existing
#   content in it is preserved (Prosediff should probably throw an error if
#   contains any hunks that cannot be found in the diff of `oldfile.txt` and
#   `newfile.txt`.
#
#   Probably all patch names (all files except the first two) should be
#   required to end in '.diff' or '.patch' (as is common with patches).
#

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
sub help_git {
    print <<"HELP_GIT_END";
If you want to use Prosediff with `git add -p` (and `git restore -p` etc.) you
need the following in your `~/.gitconfig`.

    [interactive]
        diffFilter = prosediff

If you also want commands like `git show` and `git diff` to show diffs
hilighted in the same way, you'll also need to set the following:

    [core]
        pager = prosediff | less -FRSX

The following two commands will set the two above mentioned settings:

    git config --global core.pager 'prosediff | less -FRSX'
    git config --global interactive.diffFilter prosediff

I'd recommend that you use Git's default hiliting, as well as Prosediff, since
this will give you prettily hilited headers in the `git diff` output.
(Prosediff strips away whatever colors it needs to in order to add its own, but
in lines where Prosediff do not try to hilite any original color is retained.)

Prosediff grew out of my frustration with the way `git add -p` presents
differences for multi-line files (e.g. plain text and HTML). I wanted to be
able to quickly see the whether a change was an important one, or if it was
whitespace-only (including changes in word wrapping, or indentation). But none
of the tools I tried seemed to be able to consider text across newlines. So, I
wrote Parsediff.
HELP_GIT_END
    exit 0;
}

# Split text in two, every even (including zero) element being a word, every
# odd element being a space. Words are alphanumerical strings, or individual
# punctuation characters. Whitespace and escape sequences are counted as space,
# space can also be zero-width (between punctuation characters, or punctuation
# and word).
sub tokenize {
    split /((?:\e\[[\d;]+m|\s+)+|(?<![\s\w])|(?![\s\w]))/, join '', @_;
}
sub unzip { ([@_[grep { !($_ % 2) } 0..$#_]],
             [@_[grep {   $_ % 2  } 0..$#_]]) }

# 'ESC[0K' or 'ESC[K'      Erase to EOL.
# 'ESC[0m'                 Reset styles.
# 'ESC[38;2;{r};{g};{b}m'  Set foreground color as RGB.
# 'ESC[48;2;{r};{g};{b}m'  Set background color as RGB.
# ADD    <back>+<fore>XXXXX<reset><back><clear-eol><reset>$
# DELETE <back>-      XXXXX<reset><back><clear-eol><reset>$
#
# REM <litered>  XXXXX<darkred>  ..<reset><darkred>  <clear><reset>
# ADD <litegreen>XXXXX<darkgreen>..<reset><darkgreen><clear><reset> <-- simplified
# ADD <litegreen><greenforeground>XXXXX<darkgreen>..<reset><darkgreen><clear><reset>
sub rgb_bg { sprintf("\e[48;2;%d;%d;%dm", @_) }
sub rgb_fg { sprintf("\e[38;2;%d;%d;%dm", @_) }
sub rgb_ul { sprintf("\e[58;2;%d;%d;%dm", @_) }

# The 256 color spec contains a 5x5 (216 colors) color cube, addressable with
# RGB with values 0-5. [https://en.wikipedia.org/wiki/ANSI_escape_code#8-bit]
sub rgb5 { my ($r, $g, $b) = map { $_ % 6 } @_; 16 + 36 * $r + 6 * $g + $b }
sub rgb5_fg { sprintf "\e[38;5;%dm", rgb5(@_) }
sub rgb5_bg { sprintf "\e[48;5;%dm", rgb5(@_) }
sub rgb5_ul { sprintf "\e[58;5;%dm", rgb5(@_) }

my %ansi = (                                     # DELTA COLORS
    # bg_dark_red    => rgb5_bg(1,0,0),    #  63,   0,   1
    # bg_light_red   => rgb5_bg(2,0,0),    # 144,  16,  17
    # bg_dark_green  => rgb5_bg(0,1,0),    #   0,  40,   0
    # bg_light_green => rgb5_bg(0,2,0),    #   0,  96,   0
    bg_dark_red    => rgb_bg( 75,   0,   5),     #  63,   0,   1
    bg_light_red   => rgb_bg(160,  20,  20),     # 144,  16,  17
    bg_dark_green  => rgb_bg(  0,  45,   0),     #   0,  40,   0
    bg_light_green => rgb_bg(  0,  85,   0),     #   0,  96,   0
    #fg_green       => rgb_fg(248, 248, 242),# 248, 248, 242
    clear          => "\e[K",
    reset          => "\e[49m",
);

# Do token-by-token comparison. A token is either a single punctuation
# character, or a word consisting of one or more Unicode '\w' characters. All
# space (including line wrapping and indentation) is ignored here.
sub colorize_tokendiff {
    my ($hunk1, $hunk2) = @_;
    # In order to achieve the space-ignoring stuff, each hunk is split into two
    # lists that can be interleaved again. One list contains all the tokens,
    # the other contains the spaces between each token (which may be zero).
    # These two lists always have the same number of elements, so they can be
    # zipped back together again.
    my ($token1, $space1) = unzip(tokenize($hunk1));
    my ($token2, $space2) = unzip(tokenize($hunk2));
    my ($i1, $i2, $buf1, $buf2) = (0, 0, '', '');
    my $diff2 = Algorithm::Diff->new($token1, $token2);
    while ($diff2->Next()) {
        my @token1 = $diff2->Items(1);
        my @token2 = $diff2->Items(2);
        my ($beg1, $beg2, $end1, $end2) = ('', '', '', '');
        if (not $diff2->Same()) {              # if something changed
            ($beg1, $end1) = @ansi{qw/bg_light_red   bg_dark_red/}
                if @token1;                    #   hilite stuff added
            ($beg2, $end2) = @ansi{qw/bg_light_green bg_dark_green/}
                if @token2;                    #   hilite stuff deleted
        }
        my $t1;
        for (@token1) {
            if (!$t1 && $_ ne '') { $buf1 .= $beg1; $t1 = 1 }
            $buf1 .= $_;
            my $space = $space1->[$i1++];
            if ($t1 && $space ne '') { $buf1 .= $end1; $t1 = 0 }
            $buf1 .= $space;
        }
        if ($t1) { $buf1 .= $end1 }

        my $t2;
        for (@token2) {
            if (!$t2 && $_ ne '') { $buf2 .= $beg2; $t2 = 1 }
            $buf2 .= $_;
            my $space = $space2->[$i2++];
            if ($t2 && $space ne '') { $buf2 .= $end2; $t2 = 0 }
            $buf2 .= $space;
        }
        if ($t2) { $buf2 .= $end2 }
    }
    return ($buf1, $buf2);
}

# Read patch/diff file, returning a hunk at a time. The very first hunk is a
# preamble, containing names of the files etc., and the first line of each
# (subsequent) hunk contain the `@@...@@` info (line numbers and length).
# Thereafter, in each hunk, comes the diff info: Lines starting with ' '
# (context lines), '-' (deleted lines) and '+' (added lines).
#
# Handled Diff Formats
# ====================
# Each hunk consist of one or more lines of metadata (ending in the hunk
# header), followed by diff lines (the diff lines, in turn, can be divided
# into: context lines, remove lines, add lines, and a separator line). Not all
# hunks have all of these, but a minimal hunk has, at least, a hunk header, and
# at least one remove or add line. The syntax for each of these lines is
# slightly different for different diff formats.
#
# * 'Normal diff' format is the default output off the Diff command. It uses
#   '<' and '>' to indicate added/removed lines (it doesn't have context
#   lines), and '---' as a separator line (between added and removed lines).
#   Its hunk header format is 'NUM[acd]NUM' on a separate line, where the
#   letter in the middle indicate 'add', 'change' or 'delete', and NUM is the
#   affected line numbers with an optional end line. E.g. '39a24', '62c52,55'
#   and '2,10d10'.
#
# * 'Unified diff' is the output of Git and `diff -u`. It uses '-', '+' and ' '
#   to indicate added, removed and context lines, and doesn't have a separator
#   line. Its hunk header format is '@@ -NUM +NUM @@' at the beginning of a
#   line (i.e. there might be additional information following the last '@@'),
#   where where NUM is the affected line numbers (with '-' and '+' indicating
#   the file) with an optional number of lines affected. E.g. '@@ -39 +24 @@',
#   '@@ -62 +52,3 @@' and '@@ -2,8 +10 @@'. In unified diffs, the hunk header
#   is also preceded by additional metadata, e.g. lines prefixed with '---' and
#   '+++' with file metadata, and, in the Git output, lines prefixed with
#   'diff' and 'index' giving additional context.
#
# This webpage (https://www.math.utah.edu/docs/info/diff_3.html) describes the
# various Diff formats. The two above plus another 'context format',
# 'side-by-side format, 'ed format' etc. The patch(1) manpage also has
# something to say. Patch supports the options --context, --ed, --normal and
# --unified, corresponding to the different formats.
{
    package ReadDiff;
    my $A = qr/\e\[[0-9;]*m/;                  # ANSI terminal color code
    my @re = ({
        hunk =>                                # 'NUM[,NUM](a|c|d)NUM[,NUM]'
            qr/^$A*\d+(?:,\d+)?[acd]\d+(?:,\d+)?$A*$/m,
        diff => qr/^$A*(?:[<>]$A*[ ]|---$A*$)/mx, # any diff line
        del  => qr/^$A*   [<] $A*[ ]/mx,       #   deleted
        add  => qr/^$A*    [>]$A*[ ]/mx,       #   added
        con  => undef,                         #   context (none)
        sep  => qr/^$A*---$A*$/m,              #   separator
    }, {
        hunk =>                                # '@@ -NUM[,NUM +NUM[,NUM] @@'
            qr/^$A*\@\@ -\d+(?:,\d+)? \+\d+(?:,\d+)? \@\@/m,
        diff => qr/^$A*[-+ ]/mx,               # any diff line
        del  => qr/^$A*[-]  /mx,               #   deleted
        add  => qr/^$A* [+] /mx,               #   added
        con  => qr/^$A*  [ ]/mx,               #   context
        sep  => undef,                         #   separator (none)
    });
    my ($fh, $diff_re, $head_re, @sep, @next) = ();

    # Initialize and detect diff format of the input. Return empty string if
    # format couldn't be detected, and, on success, returns four elements (for
    # matching 'added', 'deleted', 'context' and 'separator' strings).
    sub init {
        ($fh) = @_;
        @next = ();
        while (defined(my $line = <$fh>)) {
            foreach my $re (@re) {
                if ($line =~ $re->{hunk}) {
                    ($head_re, $diff_re, @sep) =
                        @{$re}{qw/hunk diff del add con sep/};
                    push(@next, $line);
                    return @sep;
                }
            }
            push(@next, $line);
        }
        return ();
    }
    # Read one hunk. Return two arrays references, 1st containing metadata
    # (last line of which is the hunk header), and 2nd containing diff lines.
    sub read {
        my @meta = splice(@next);
        return (@meta ? \@meta : ()) if eof($fh);
        my ($done, @buf);
        while (<$fh>) {
            if (/$head_re/) {
                push(@next, $_);
                last;
            }
            $done = 1 if !/$diff_re/;
            if ($done) {
                push(@next, $_);
            } else {
                push @buf, $_;
            }
        }
        return (\@meta, \@buf);
    }
}

# Usage: colorize_diff(TEXT1, TEXT2, SEPARATOR, DEL_REGEX, ADD_REGEX);
sub colorize_diff {
    my @txt = (shift, shift); my ($sep, @re) = @_;
    my @color = @ansi{qw/bg_light_red bg_light_green/};
    my $A = qr/\e\[[0-9;]*m/;                  # ANSI terminal color code
    if ($txt[0] and $txt[1]) {                 # CHANGED
        @color = @ansi{qw/bg_dark_red bg_dark_green/};
        # Strip diff line prefixes (e.g. '-' and '+', or '< ' and '> ') from
        # beginning of lines in @txt, and keep them in @sep (however, leave any
        # ANSI styles in the prefixes in @txt).
        my @sep = map {
            $txt[$_] =~ s{$re[$_]}{            # strip prefix from @txt
                join('', $& =~ m/($A)/g);
            }ge;
            $& =~ s/$A//gr;                    # put prefix in @sep
        } (0..1);
        @txt = colorize_tokendiff(@txt);
        $txt[$_] =~ s/^/$sep[$_]/gm for 0..1;  # put headers back again
    }
    for (0..1) {                               # DELETED/ADDED
        next unless $txt[$_];
        $txt[$_] =~ s/^/$color[$_]$ansi{clear}/gm;
        $txt[$_] =~ s/$/$ansi{reset}/;
    }
    return $txt[0] . $sep . $txt[1];
}

# Normalize and simplify ANSI 'ESC[...m' sequences (used for style & color).
# Unknown 'ESC[...m' sequences are removed, while all other types ANSI codes
# are left untouched. Simplification removes any redundant color codes (e.g.
# the sequence '<red><reset><green><red>' would be collapsed to <red>), and
# general <reset> code ('ESC[m' or 'ESC[0m') is rewritten to only the styles &
# colors currently active. This is useful if you want to add your own ANSI
# codes without having them messed up by the commonly used '\e[0m' code.
#
# NB: Also strips out background color. (Background color handling is commented
# out below, meaning that background colors will be stripped off from the
# input.)
sub normalize_ansi {
    $_[-1] =~ s/$/\e[m/ if @_;                 # add trailing reset
    my %reset = ();                            # reset codes used (on 'ESC[m')
    my %ansi = map {                           # ANSI codes (CODE => NAME)
        my ($name, @num) = @$_;
        $reset{$num[0]} = $name;               #   reset codes (CODE => NAME)
        map { ($_ => $name) } @num;
    } (# name            unset,set,set...
        [bold            => 22,  1,  2],
        [italic          => 23,  3    ],
        [underline       => 24,  4, 21],
        [blink           => 25,  5,  6],
        [inverse         => 27,  7    ],
        [hidden          => 28,  8    ],
        [strikethrough   => 29,  9    ],
        [foreground      => 39, 38, 30..37,  90.. 97],
        #[background      => 49, 48, 40..47, 100..107],
        [overline        => 55, 53    ],
        [underline_color => 59, 58    ],
        [superscript     => 75, 73, 74],
    );
    # Recognized reset codes, not output when rewriting 'ESC[m'.
    my %reset_recog = (%reset, '4:0' => 'underline');
    my $COLOR = qr#(?:
                       5   ;\d+     |
                       2(?:;\d+){3} )#x;
    my %prev;                                  # previous state (NAME => CODE)
    for (@_) {
        s{(\e\[[0-9;:]*m)+}{                   # one or more adjacent ANSI code
            local $_ = $&;
            s#\e\[(.*?)m#$1;x;#g;              #   strip 'ESC[' and 'm'

            # Collect state transition in to make %cur (NAME => CODE).
            my %cur;                           #   state for this ANSI code
            while ($_) {                       #   go thru entire ANSI code
                s#^x;##x && next;              #     separator between codes
                s#^0*##;                       #     strip any leading zeroes
                my $cmd = do { s#^\d*##; $& }; #     command (may be empty)
                my $arg = do {                 #     args (may be empty)
                    s#^(:\d*)+## ||            #       colon delimited
                        ($cmd =~ /^(38|48|58)$/#       semicolon delimited
                         && s#^;$COLOR##)      #         (for some commands)
                        ? $& : '';
                };
                s#;(x;)*##;
                if ($cmd eq  '') {             # 'ESC[0m' = reset ALL values
                    @cur{values %reset} = keys %reset;
                } else {                       # found a command
                    my $ansi_name = $ansi{$cmd};
                    $cur{$ansi_name} = $cmd . $arg
                        if $ansi_name;
                }
            }
            # Update previous state & current ANSI code.
            for (keys %cur) {                  # for each style
                my $value = $cur{$_};
                if ($reset_recog{$value}) {    # set to reset style/color
                    if ($prev{$_}) {           #   is in previous state
                        $cur{$_} = $value;     #     use ANSI erase code
                        delete $prev{$_};      #     remove from state
                    } else {                   #   not in previous state
                        delete $cur{$_};       #     nevermind
                    }
                } elsif ($value eq ($prev{$_} // '')) {
                    delete $cur{$_};
                } else {                       # set to value
                    $prev{$_} = $value;        #   add to previous state
                }
            }
            !%cur ? '' : (sprintf "\e[%sm", join ';', sort {
                no warnings "numeric";
                "0$a" <=> "0$b" or $a cmp $b;
            } @cur{keys %cur});
        }gex;
    }
}

sub filter {
    my ($fh) = @_;
    my ($del_re, $add_re, $context_re, $sep_re) = ReadDiff::init($fh) or do {
        # Input is not a diff. Just let it through unmodified & exit.
        print @{ ReadDiff::read() // [] };
    };
    while (my ($head, $diff) = ReadDiff::read()) {
        normalize_ansi(@$diff);                # strip ANSI background color
        print @$head;                          # output @...@ header
        my ($txt1, $txt2, $sep) = ('', '', '');
        foreach (@$diff) {
            if ($del_re and /$del_re/) { $txt1 .= $_; next }
            if ($add_re and /$add_re/) { $txt2 .= $_; next }
            if ($sep_re and /$sep_re/) { $sep  .= $_; next }
            if ($context_re and /$context_re/) {
                print colorize_diff($txt1, $txt2, $sep, $del_re, $add_re);
                ($txt1, $txt2, $sep) = ('', '', '');
                print;
            }
        }
        print colorize_diff($txt1, $txt2, $sep, $del_re, $add_re);
    }
}

###############################################################################
# Main

local $SIG{__DIE__} = sub {
    die @_ if $^S;                             # abort if called inside eval
    my $more = (my $msg = "@_") =~ s/[.]$//;   # ending in '.' = extra help
    die "$PROGRAM: $msg",
        $more && "Try '$PROGRAM --help' for more information.\n";
};

my %opt = (cmd => 'diff', pager => 'less -FRSX', pager_args => []);
my @arg;
@ARGV = map { decode } @ARGV;
while (@ARGV) {
    local $_ = shift;
    /^    --               $/x and push(@arg, @ARGV), last;
    /^    --command(=(.*))?$/x and ($opt{cmd} = $2 // shift()), next;
    /^(-h|--help)          $/x and help();
    /^    --help-git       $/x and help_git();
    /^    --pager(=(.*))?  $/x and ($opt{pager} = $2 // shift()), next;
    /^(-V|--version)       $/x and version();
    /^[+]                   /x and push(@{$opt{pager_args}}, $_), next;
    push(@arg, $_);
}

no warnings 'exec';
my $fh = (-t STDIN || @arg) ? do {             # wrapper mode
    # Run diff and filter its output.
    open(my $x, '-|',  split(/\s+/, $opt{cmd}), @arg)
        or die "Cannot run command '$opt{cmd}': $!\n";
    $x;
} : *STDIN;                                    # filter mode

# If not piped, use pager.
open(STDOUT, '|-', split(/\s+/, $opt{pager}), @{$opt{pager_args}})
    or die "Cannot run command '$opt{pager}': $!\n"
    if -t STDOUT;

filter($fh);

close($fh) or do {
    die "Cannot close 'diff' output: $!" if $!;
};
exit $? >> 8;

#[eof]
