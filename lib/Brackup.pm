package Brackup;
use strict;
use vars qw($VERSION);
$VERSION = '1.02';

use Brackup::Config;
use Brackup::ConfigSection;
use Brackup::File;
use Brackup::PositionedChunk;
use Brackup::StoredChunk;
use Brackup::Backup;
use Brackup::Root;     # aka "source"
use Brackup::Restore;
use Brackup::Target;
use Brackup::BackupStats;

1;
