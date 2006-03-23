use ExtUtils::MakeMaker;
WriteMakefile( NAME => 'Brackup',
               VERSION_FROM => 'brackup',
               PREREQ_PM              => {
                   'DBD::SQLite' => 0,
                   'Digest::SHA1' => 0,
                   'DBI' => 0,
               },
               EXE_FILES => [ 'brackup' ],
               ($] >= 5.005 ?
                (ABSTRACT_FROM => 'brackup',
                 AUTHOR     => 'Brad Fitzpatrick <brad@danga.com>') : ()),
               );

