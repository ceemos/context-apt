#!/usr/bin/perl
#kate: indent-width 3; indent-mode normal; dynamic-word-wrap on; line-numbers on; space-indent on; mixed-indent off;
#Run_: ./apt2pdf.pl ../apt/format.txt
use 5.010;
use strict;
use warnings;
use autodie;
use IO::Dir;
use IO::File;
use Data::Dumper;

use Method::Signatures::Simple;

{  package APTParser;
   use Any::Moose; use Method::Signatures::Simple; use Data::Dumper;
   
   {  package APTParser::State;
      use Any::Moose; use Method::Signatures::Simple;
      
      has 'parser', is => 'ro', isa => 'APTParser', required => 1;
      
      method handleLine ($line) {
         chomp $line;
         if ($line ~~ /^(\s+)\*\s/) {
            say ("Default:Have Enum");
            $self->parser()->enterState (APTParser::State::Enumeration->new (parser => $self->parser(), level => $1));
            $self->parser()->parseLine ($line);
         } elsif ($line ~~ /^\s+[^\s]/){
            say ("Default:Have a Paragraph");
            $self->parser()->enterState (APTParser::State::Paragraph->new (parser => $self->parser()));
            $self->parser()->parseLine ($line);
         } elsif ($line ~~ /^(-+)(\.\w\w?\w?\w?)\s*$/) {
            say ("Default:Have Code");
            $self->parser()->enterState (APTParser::State::Sourcecode->new (parser => $self->parser()));
            $self->parser()->parseLine ($line);
         } elsif ($line ~~ /^(\+|-)-+/) {
            say ("Default:Have Verbatim");
            $self->parser()->enterState (APTParser::State::Verbatim->new (parser => $self->parser()));
            $self->parser()->parseLine ($line);
         } else {
            say ("Default:Have Line $.: $line");
         }
      }
      method startState () { }
      method stopState () { }
   }
   
   {  package APTParser::State::Document;
      use Any::Moose; use Method::Signatures::Simple; 
      extends 'APTParser::State';
      
      override handleLine => method ($line) {
         if ($line ~~ /^\s+------+\s*$/) {
            say ("Default:Have Head");
            $self->parser()->enterState (APTParser::State::Head->new (parser => $self->parser()));
            $self->parser()->parseLine ($line);
         } elsif ($line ~~ /^(\*|\w|\d)/) {
            say ("Default:Have Sec");
            $self->parser()->enterState (APTParser::State::SectionTitle->new (parser => $self->parser()));
            $self->parser()->parseLine ($line);
         } else {
            super ();
         }
      };
      
      override startState => method () {
         $self->parser->printLine ("\\input setup.tex\n");
         $self->parser->printLine ("\\starttext\n");
      };
      override stopState => method () {
         $self->parser->printLine ("\\stoptext");
      };
   }
   {  package APTParser::State::Paragraph;
      use Any::Moose; use Method::Signatures::Simple;
      extends 'APTParser::State';
      
      override handleLine => method ($line) {
         chomp $line;
         if ($line ~~ /^\s*$/){
            say ("Par:Have a empty Line at $.");
            $self->parser()->leaveState();
         } else {
            say ("ParLine $.: $line");
            $self->parser->printLinePP ($line . "\n");
         }
      };
      override startState => method () {
         #$self->parser->printLine ("\n\n");
      };
      override stopState => method () {
         $self->parser->printLine ("\n\n");
      };
   }
   {  package APTParser::State::Head;
      use Any::Moose; use Method::Signatures::Simple;
      extends 'APTParser::State';
      
      has 'entrys', is => 'ro', default => sub {[]}; 
      
      override handleLine => method ($line) {
         chomp $line;
         if ($line ~~ /^\s*-*\s*$/){
            say ("Head:Have Separator");
            push $self->entrys(), "";
            if ($self->entrys() == 4) {
               $self->parser()->leaveState();
            }
         } else {
            my $e = $self->entrys();
            $line =~ s/^\s+|\s+$//g ;
            push $e, pop ($e) . $line;
            say ("Head:Entry: $line");
            if (@$e == 3 && @$e[-1] ne "") {
               $self->parser()->leaveState();
            }
         }
      };
      override stopState => method () {
         my $e = $self->entrys();
         my $title = @$e[0];
         my $author = @$e[1];
         my $date = @$e[2];
         $self->parser->printLine ("\\title{ ");
         $self->parser->printLinePP ("$title");
         $self->parser->printLine ("} \n \\Author{");
         $self->parser->printLinePP ("$author");
         $self->parser->printLine ("} \n ");
         $self->parser->printLinePP ("$date \n\n");
      };
   }
   {  package APTParser::State::SectionTitle;
      use Any::Moose; use Method::Signatures::Simple;
      extends 'APTParser::State';
      
      has 'level', is => 'rw', default => "";
      
      override handleLine => method ($line) {
         chomp $line;
         $line =~ /^(\**)\s*([^\*]+)$/;
         $self->level ($1);
         say ("Sec:Have Sec at $.: $2, level $1");
         
         my %types = ("" => "chapter", "*" => "section", 
                      "**" => "subsection", "***" => "subsubsection");
         my $t = $types{$self->level()};
         
         $self->parser->printLine ("\n\\$t {");
         $self->parser->printLinePP ($2);
         $self->parser->printLine ("}\n");
         
         $self->parser()->leaveState();
      };
   }
   {  package APTParser::State::Enumeration;
      use Any::Moose; use Method::Signatures::Simple;
      extends 'APTParser::State';
      
      has 'level', is => 'ro', default => " "; 
      
      override handleLine => method ($line) {
         chomp $line;
         my $id = $self->level();
         if ($line ~~ /^($id\s*)\*\s(.*)$/){
            if ($1 eq $id) {
               say ("Enum: Have Point");
               $self->parser->printLine ("\\item\n");
               $line = "$id$2";
               $self->parser->parseLine ($line);
            } else {
               say ("Enum: Have Subenum");
               $self->parser()->enterState (APTParser::State::Enumeration->new (parser => $self->parser(), level => $1));
               $self->parser()->parseLine ($line);
            }
         } elsif ($line ~~ /^\s*\[]\s*$/) {
            say ("Enum: Have force end");
            $self->parser()->leaveState();
         } elsif (!($line ~~ /^$id(.*)$/)) {
            say ("Enum: Have less ident");
            $self->parser()->leaveState();
            $self->parser()->parseLine ($line);
         } else {
            super ();
         }
      };
      override startState => method () {
         $self->parser->printLine ("\\startitemize\n");
      };
      override stopState => method () {
         $self->parser->printLine ("\\stopitemize\n");
      };
   }
   {  package APTParser::State::Verbatim;
      use Any::Moose; use Method::Signatures::Simple;
      extends 'APTParser::State';
      
      has 'type', is => 'rw', default => "";
      
      override handleLine => method ($line) {
         chomp $line;
         if ($self->type() eq "" && $line ~~ /^((\+|-)-+(\+|-))/){
            say ("Verb:Have Box at $. type $2, border $1");
            $self->type ($1);
         } else {
            my $border = $self->type();
            if (index ($line, $border) == 0) {
               $self->parser()->leaveState();
            } else {
               say ("VerbLine $.: $line");
               $self->parser->printLine ($line . "\n");
            }
         }
      };
      override startState => method () {
         $self->parser->printLine ("\\input setup.tex\n");
         $self->parser->printLine ("\\startverbbox\n");
      };
      override stopState => method () {
         $self->parser->printLine ("\\stopverbbox");
      };
   }
   {  package APTParser::State::Sourcecode;
      use Any::Moose; use Method::Signatures::Simple;
      extends 'APTParser::State';
      
      has 'type', is => 'rw', default => "";
      has 'tempfile', is => 'rw';
      has 'tempname', is => 'rw';
      
      override handleLine => method ($line) {
         chomp $line;
         if ($self->type() eq "" && $line ~~ /^(-+)(\.\w\w?\w?\w?)\s*$/) {
            say ("Code:Have Box at $. type $2, border $1");
            $self->type ($1);
            my $tempname = "~temp$2";
            my $file = IO::File->new ($tempname, "w");
            $self->tempfile ($file);
            $self->tempname ($tempname);
         } else {
            my $border = $self->type();
            if (index ($line, $border) == 0) {
               $self->parser()->leaveState();
            } else {
               say ("Code $.: $line");
               $self->tempfile()->print ("$line\n");
            }
         }
      };
      override startState => method () {
         $self->parser->printLine ("\n\n\\startcodebox\n");
      };
      override stopState => method () {
         $self->tempfile()->close();
         my $INFILE = $self->tempname(); 
         my $OUTFILE = "~temp.htm";
         system (q|bash -c "vim +'set nonumber' \
                  +'syntax enable' \
                  +'let html_use_css=1' \
                  +'TOhtml' \
                  +'/<pre>/,/<\/pre>/d a' \
                  +'g/./d' \
                  +'1pu! a' \
                  +'\$d' \
                  +'wq! | . qq | $OUTFILE' \\
                  +'q!' $INFILE" |);
         my $htm = IO::File->new ($OUTFILE, "r");
         while (my $line = <$htm>) {
            $line =~ s|&quot;|"|g;
            $line =~ s|&lt;|<|g;
            $line =~ s|&gt;|>|g;
            $line =~ s|</?pre>||g;
            $line =~ s|<span class="(\w+)">|[[\\$1 |g;
            $line =~ s|</span>|]]|g;
            $self->parser->printLine ($line);
         }
         $self->parser->printLine ("\n\\stopcodebox\n");
      };
   }
   
   
   has 'state' => (
      is => 'ro', 
      isa => 'ArrayRef[APTParser::State]', 
      default => sub {
         my $self = shift;
         my $s = APTParser::State::Document->new (parser => $self);
         $s->startState();
         return [$s]; },
      lazy => 1
   );
   
   has 'outfile', is => 'ro', required => 1;
   
   method enterState ($state) {
      $state->startState();
      push $self->state(), $state;
   }
   
   method leaveState () {
      my $oldState = pop $self->state();
      $oldState->stopState();
      
   }
   
   method finish () {
      while (defined (my $s = pop $self->state())) {
         $s->stopState();
      }
   }
   
   method parseLine ($line) {
      if ($line ~~ /^~~/) {
         return; # Kommentar
      }
      my $states = $self->state();
      @$states[-1]->handleLine ($line);
   }
   
   method printLine ($line) {
      $self->outfile()->print ($line);
   }
   
   method printLinePP ($line) {
      # Sonderzeichen
      $line =~ s/\\/~/g;
      $line =~ s/~~/\\#/g;
      $line =~ s/\|/\\Pipe /g;
      $line =~ s/{/ /g;
      $line =~ s/}/ /g;
      $line =~ s/~/ /g;
      
      # Einfaches HL
      $line =~ s/(?<!~)<<<([^>]*)>>>/{\\tt $1} /g;
      $line =~ s/(?<!~)<<([^>]*)>>/{\\bf $1} /g;
      $line =~ s/(?<!~)<([^>]*)>/{\\it $1} /g;
      
      $self->outfile()->print ($line);
   }
}

func readFile ($file, $parser) {
   my $aptfile = IO::File->new ($file, "r");
   while (my $line = <$aptfile>) {
      $parser->parseLine ($line);
   }
}

my $o = IO::File->new ("out.tex", "w");

my $p = APTParser->new (outfile => $o);

if (@ARGV != 0) {

   for my $file (@ARGV) {
      readFile ($file, $p);
   }
   
} else {

   my $dir = "/home/marcel/Dokumente/sq/blatt2";
   my $d = IO::Dir->new ($dir);
   my @files = $d->read;
   
   @files = sort @files;
   
   for my $file (@files) {
   
      if ($file ~~ /\.txt$/) {
         say ("Found file $file");
         readFile ("$dir/$file", $p);
      }
   } 
}

say ("finish.");
$p->finish();
$o->close();

system ('bash -c ". /opt/context-minimals/setuptex; context out.tex"');

