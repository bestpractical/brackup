#!/usr/bin/perl
use 5.006;
use strict;
use ExtUtils::MakeMaker;

WriteMakefile( NAME            => 'Brackup',
               VERSION_FROM    => 'lib/Brackup.pm',
               EXE_FILES       => [ 'brackup', 'brackup-restore', 'brackup-target', 
                                    'brackup-mount', 'brackup-verify-inventory',
                                    'brackup-verify-chunks',
                                  ],
               PREREQ_PM       => {
                   'ExtUtils::Manifest' => 1.52,    # For spaces in files in MANIFEST
                   'DBD::SQLite'        => 0,
                   'Digest::SHA'        => 0,
                   'DBI'                => 0,
                   'File::Temp'         => 0.19,    # require a seekable File::Temp + EXLOCK support
                   'IO::InnerFile'      => 0,
                   'String::Escape'     => 0,
                   'Try::Tiny'          => 0,
                   'Test::More'         => 0.88,    # For done_testing
                   'JSON'               => 0,
               },
               ABSTRACT_FROM => 'lib/Brackup.pm',
               AUTHOR     => 'Brad Fitzpatrick <brad@danga.com>',
               );


