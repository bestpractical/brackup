#!/usr/bin/perl
use strict;
use ExtUtils::MakeMaker;

WriteMakefile( NAME            => 'Brackup',
               VERSION_FROM    => 'brackup',
               EXE_FILES       => [ 'brackup', 'brackup-restore' ],
               PREREQ_PM       => {
                   'DBD::SQLite'  => 0,
                   'Digest::SHA1' => 0,
                   'DBI'          => 0,
               },
               ABSTRACT_FROM => 'brackup',
               AUTHOR     => 'Brad Fitzpatrick <brad@danga.com>',
               );


