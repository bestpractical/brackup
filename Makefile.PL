#!/usr/bin/perl
use strict;
use ExtUtils::MakeMaker;

WriteMakefile( NAME            => 'Brackup',
               VERSION_FROM    => 'lib/Brackup.pm',
               EXE_FILES       => [ 'brackup', 'brackup-restore', 'brackup-target', 
                                    'brackup-mount', 'brackup-verify-inventory', ],
               PREREQ_PM       => {
                   'DBD::SQLite'  => 0,
                   'Digest::SHA1' => 0,
                   'DBI'          => 0,
                   'String::Escape' => 0,
                   'IO::InnerFile'  => 0,
                   'File::Temp'     => 0.19,        # require a seekable File::Temp + EXLOCK support
                   'ExtUtils::Manifest' => 1.52,    # For spaces in files in MANIFEST
                   'Test::More'         => 0.88,    # For done_testing
               },
               ABSTRACT_FROM => 'lib/Brackup.pm',
               AUTHOR     => 'Brad Fitzpatrick <brad@danga.com>',
               );


