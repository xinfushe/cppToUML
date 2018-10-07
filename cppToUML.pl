#!/usr/bin/perl

use v5;
use strict;
use warnings;

use Getopt::Long;

use StoreClass;

my $help = '';
GetOptions('h' => \$help, 'help' => \$help);

sub printUsage {
  print "Usage: ./generateUML <comma separated list of files containing C++= classes>\n\n";

  print "Available flags:\n";
  print "\t-h,-help\tPrint help\n\n";
}

sub printExample {
  print "Example usage:\t./.generateUML /path/to/header/file1 /path/to/head= er/file2\n";
  print "Output: \@plantuml output of given input files to stdout\n\n";
  print "\@startuml\nParentClass <|-- File1\nclass File1 {\n+void publicMem= ber()\n#int protectedVar;\n}\n\n";
  print "ParentClass2 <|-- File2\nclass File2 {\n-void privateMember()\n}\n= \@enduml\n";
}

if($help)
{
  printUsage();
  printExample();
  exit;
}


if($#ARGV == -1)
{
  print "Error! Expecting file input\n\n";
  printUsage();
  exit;
}

my @classes = ();

# Iterate over argv
foreach(@ARGV)
{
  my @openClasses = ();
  if(open(FILE, $_))
  {
    my $multiLineInheritance = 0;
    my $multiLineComment = 0;
    my $multiLineVarOrFunc = 0;
    my $multiLineTemplate = 0;
    my $multiLine = "";
    foreach (<FILE>)
    {
      chomp;
      # Start of multiline comment
      if($_ =~ /(?:^\h*\/\*).*(?<!\*\/)/) {  $multiLineComment = 1; next; }

      # Skip if new line is empty or starts with a comment
      next if $_ =~ /^\h*(?:$|\/\/)/;

      if($multiLineComment)
      {
        if($_ =~ /\*\//) { $multiLineComment = 0; }
        next;
      }
      elsif($multiLineInheritance)
      {
        $multiLine .= " $_";
        if(index($_,'{') != -1)
        {
            # As we are parsing inheritance, we know that the array isn't e= mpty
            my $class = $openClasses[-1];
            $multiLineInheritance = 0;
            while($multiLine =~ /(public|private|protected)\h+((?:\w+::)*\w+)/g)
            {
              $class->addParent($1,$2);
            }
            $multiLine = "";
        }
        next;
      }
      elsif($multiLineVarOrFunc)
      {
        $multiLine .= " $_";
        if(index($_,';') != -1)
        {
          my $class = $openClasses[-1];
          $multiLineVarOrFunc = 0;
          if(   $multiLine =~ /((?:\w+::)*\w+\h+\w+\(.*\));/) { $class->addMemberFunction($1);    }
          elsif($multiLine =~ /((?:\w+::)*\w+\h+[\w\[\]]+);/)       { $class->addMemberVariable($1);    }
          $multiLine = "";
        }
        next;
      }
      elsif($multiLineTemplate)
      {
        $multiLine .= " $_";
        # If template <> are balanced and a class definition is on the current line
        # or a function/variabel declaration is closed by ';'
        if($multiLine =~ /<(?>[^<>]|(?R))*>/ and 
           $multiLine =~ /(?>class|struct).*{|;/)
        {
          $multiLineTemplate = 0;
          if($multiLine =~ /class|struct/)
          {
            # Create new class
            if($multiLine =~ /^\h*(template\h*<.*>)\h+(class|struct)\h+(\w+)/)
            {
              my $class = new StoreClass("$2 $3");
              push @openClasses, $class;
              $class->addTemplateParameters($1);


              while($multiLine =~ /(public|private|protected)\h+((?:\w+::)*[\w<>]+)/g)
              {
                $class->addParent($1,$2);
              }
              # Reset line
              $multiLine = "";
            }
          }
          elsif($multiLine =~ /;/)
          {
            # If there is a class being parsed, the multiline template is a member function or variable
            if(@openClasses)
            {
              my $class = $openClasses[-1];
              # Add member or variable

            }
            $multiLine = "";
            $multiLineTemplate = 0;
          }
          
        }
        next;
      }

      # When done with a class, go to next line
      if(@openClasses and $_ =~ /^};$/)
      {
        push @classes, pop @openClasses;
        next;
      }

      # If a class is found
      if($_ =~ /^\h*(class|struct)\h+(\w+)/)
      {
        my $class = new StoreClass("$1 $2");
        push @openClasses, $class;

        # If there is inheritance but the class opening braces
        # aren't on the same line as class definition
        if(index($_,":") != -1 and index($_,'{') == -1)
        {
          $multiLineInheritance = 1;
          $multiLine = $_;
          next;
        }

        while($_ =~ /(public|private|protected)\h+((?:\w+::)*\w+)/g)
        {
          $class->addParent($1,$2);
        }
        next;
      }

      # If a template appears, regardless if an open class exists or not
      if($_ =~ /^\h*template/)
      {
        $multiLine = $_;
        $multiLineTemplate = 1;
        next;
      }

      if(@openClasses)
      {
        my $class = $openClasses[-1];
        if($_ =~ /^\h*(public|private|protected):/) { $class->changeAccessModifier($1); }
        elsif($_ =~ /((?:\w+::)*\w+\h+\w+\(.*\));/) { $class->addMemberFunction($1);    }
        elsif($_ =~ /((?:\w+::)*\w+\h+[\w\[\]]+);/)       { $class->addMemberVariable($1);    }
        elsif($_ =~ /((?:\w+::)*\w+[\w\(,\h]+(?<!;$))/)     # No ending ';', multiline variable or function
        {
            $multiLine = $_;
            $multiLineVarOrFunc = 1;
        }
      }
    }
    close(FILE);
  }
  else
  {
    print "Could not open file '$_' $!\n";
  }
}

print "\@startuml\n";
foreach my $class(@classes)
{
  bless $class, "StoreClass";
  $class->dump();
}
print "\@enduml\n";

