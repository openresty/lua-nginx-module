#!/usr/bin/env perl

use strict;
use warnings;
use bytes;

my @nl_counts;
my $last_nl_count_level;

my @bl_counts;
my $last_bl_count_level;

sub fmt_pos ($) {
    (my $s = $_[0]) =~ s{\#(.*)}{/"$1"};
    $s;
}

sub fmt_mark ($$) {
    my ($tag, $s) = @_;
    my $max_level = 0;
    while ($s =~ /([<>])\1*/g) {
        my $level = length $&;
        if ($level > $max_level) {
            $max_level = $level;
        }
    }

    my $times = $max_level + 1;
    if ($times > 1) {
        $s = " $s ";
    }
    return $tag . ('<' x $times) . $s . ('>' x $times);
}

print "=encoding utf-8\n\n";

while (<>) {
    if ($. == 1) {
        # strip the leading U+FEFF byte in MS-DOS text files
        my $first = ord(substr($_, 0, 1));
        #printf STDERR "0x%x", $first;
        #my $second = ord(substr($_, 2, 1));
        #printf STDERR "0x%x", $second;
        if ($first == 0xEF) {
            substr($_, 0, 1, '');
            #warn "Hit!";
        }
    }
    s{\[(http[^ \]]+) ([^\]]*)\]}{$2 (L<$1>)}gi;
    s{ \[\[ ( [^\]\|]+ ) \| ([^\]]*) \]\] }{"L<$2|" . fmt_pos($1) . ">"}gixe;
    s{<code>(.*?)</code>}{fmt_mark('C', $1)}gie;
    s{'''(.*?)'''}{fmt_mark('B', $1)}ge;
    s{''(.*?)''}{fmt_mark('I', $1)}ge;
    if (s{^\s*<[^>]+>\s*$}{}) {
        next;
    }

    if (/^\s*$/) {
        print "\n";
        next;
    }

=begin cmt

    if ($. == 1) {
        warn $_;
        for my $i (0..length($_) - 1) {
            my $chr = substr($_, $i, 1);
            warn "chr ord($i): ".ord($chr)." \"$chr\"\n";
        }
    }

=end cmt
=cut

    if (/(=+) (.*) \1$/) {
        #warn "HERE! $_" if $. == 1;
        my ($level, $title) = (length $1, $2);
        collapse_lists();

        print "\n=head$level $title\n\n";
    } elsif (/^(\#+) (.*)/) {
        my ($level, $txt) = (length($1) - 1, $2);
        if (defined $last_nl_count_level && $level != $last_nl_count_level) {
            print "\n=back\n\n";
        }
        $last_nl_count_level = $level;
        $nl_counts[$level] ||= 0;
        if ($nl_counts[$level] == 0) {
            print "\n=over\n\n";
        }
        $nl_counts[$level]++;
        print "\n=item $nl_counts[$level].\n\n";
        print "$txt\n";
    } elsif (/^(\*+) (.*)/) {
        my ($level, $txt) = (length($1) - 1, $2);
        if (defined $last_bl_count_level && $level != $last_bl_count_level) {
            print "\n=back\n\n";
        }
        $last_bl_count_level = $level;
        $bl_counts[$level] ||= 0;
        if ($bl_counts[$level] == 0) {
            print "\n=over\n\n";
        }
        $bl_counts[$level]++;
        print "\n=item *\n\n";
        print "$txt\n";
    } else {
        collapse_lists();
        print;
    }
}

collapse_lists();

sub collapse_lists {
    while (defined $last_nl_count_level && $last_nl_count_level >= 0) {
        print "\n=back\n\n";
        $last_nl_count_level--;
    }
    undef $last_nl_count_level;
    undef @nl_counts;

    while (defined $last_bl_count_level && $last_bl_count_level >= 0) {
        print "\n=back\n\n";
        $last_bl_count_level--;
    }
    undef $last_bl_count_level;
    undef @bl_counts;
}

