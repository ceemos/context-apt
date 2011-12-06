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
      
      method handleLine ($line) { }
      method startState () { }
      method stopState () { }
   }
   
   {  package APTParser::State::Document;
      use Any::Moose; use Method::Signatures::Simple; 
      extends 'APTParser::State';
      
      override handleLine => method ($line) {
         chomp $line;
         if ($line ~~ /^\s+\w/){
            say ("Doc:Have a Paragraph");
            $self->parser()->enterState (APTParser::State::Paragraph->new (parser => $self->parser()));
            $self->parser()->parseLine ($line);
         } elsif ($line ~~ /^\s+------+\s*$/) {
            say ("Doc:Have Head");
            $self->parser()->enterState (APTParser::State::Head->new (parser => $self->parser()));
            $self->parser()->parseLine ($line);
         } elsif ($line ~~ /^(\*|\w|\d)/) {
            say ("Doc:Have Sec");
            $self->parser()->enterState (APTParser::State::SectionTitle->new (parser => $self->parser()));
            $self->parser()->parseLine ($line);
         } elsif ($line ~~ /^(\s+)\*\s/) {
            say ("Doc:Have Enum");
            $self->parser()->enterState (APTParser::State::Enumeration->new (parser => $self->parser(), level => $1));
            $self->parser()->parseLine ($line);
         } elsif ($line ~~ /^(\+|-)-+/) {
            say ("Doc:Have Verbatim");
            $self->parser()->enterState (APTParser::State::Verbatim->new (parser => $self->parser()));
            $self->parser()->parseLine ($line);
         } else {
            say ("Doc:Have Line $.: $line");
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
         $self->parser->printLinePP ("\\title{ $title} \n \\Author{$author} \n $date \n\n");
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
               $self->parser()->enterState (APTParser::State::Paragraph->new (parser => $self->parser()));
               $self->parser()->parseLine ("   $2");
            } else {
               say ("Enum: Have Subenum");
               $self->parser()->enterState (APTParser::State::Enumeration->new (parser => $self->parser(), level => $1));
               $self->parser()->parseLine ($line);
            }
         } elsif ($line ~~ /^\s*\[]\s*$/) {
            say ("Enum: Have force end");
            $self->parser()->leaveState();
         } elsif ($line ~~ /^($id\s*)(.+)$/){
            say ("Enum: Have Paragraph");
            $self->parser()->enterState (APTParser::State::Paragraph->new (parser => $self->parser()));
            $self->parser()->parseLine ("   $2");
         } elsif ($line ~~ /^(\s+)(.*)$/) {
            say ("Enum: Have less ident");
            $self->parser()->leaveState();
            $self->parser()->parseLine ($line);
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
         $self->parser->printLine ("\n\n\\startverbbox\n");
      };
      override stopState => method () {
         $self->parser->printLine ("\n\\stopverbbox\n");
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
      my $states = $self->state();
      @$states[-1]->handleLine ($line);
   }
   
   method printLine ($line) {
      $self->outfile()->print ($line);
   }
   
   method printLinePP ($line) {
      $line =~ s/(?<!\\)<<</{\\tt /g;
      $line =~ s/(?<!\\)<</{\\bf /g;
      $line =~ s/(?<!\\)</{\\it /g;
      $line =~ s/(?<!\\)>+/} /g;
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

