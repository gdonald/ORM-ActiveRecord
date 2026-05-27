use ORM::ActiveRecord::DB;
use ORM::ActiveRecord::Support::DatabaseUrl;

unit module SpecHelpers;

sub current-adapter-name(--> Str) is export {
  return 'sqlite' without %*ENV<DATABASE_URL>;
  my %c = parse-database-url(%*ENV<DATABASE_URL>);
  given (%c<adapter> // '').lc {
    when 'pg' | 'postgres' | 'postgresql' { 'pg' }
    when 'mysql' | 'mysql2' | 'mariadb'   { 'mysql' }
    when 'sqlite' | 'sqlite3'             { 'sqlite' }
    default                                { 'sqlite' }
  }
}

sub db-available(--> Bool) is export {
  my $adapter = DB.shared.adapter;
  $adapter.defined && $adapter.is-connected;
}

sub rollback-if-in-transaction is export {
  my $adapter = DB.shared.adapter;
  return unless $adapter.defined;
  try $adapter.exec('ROLLBACK') if DB.shared.is-in-transaction;
}

# Canonical tables created by db/migrate/, listed child → parent so that
# DELETEs respect every declared FK. Used by `clean-shared-tables` so each
# behave spec touching shared tables can start from a clean slate without
# tripping over a sibling spec's leftover rows.
my @SHARED-TABLE-CLEAN-ORDER = <
  posts_tags
  scarticles_sctags
  pictures
  attachments
  comments
  cpcomments
  scarticles
  scprofiles
  articles
  subscriptions
  thsubs
  ownerships
  belongings
  pages
  profiles
  accounts
  passports
  towns
  regions
  employees
  qcdocs
  scauthors
  cpauthors
  thmags
  sctags
  tags
  posts
  cpposts
  magazines
  contacts
  contracts
  clients
  persons
  images
  books
  games
  logs
  phbooks
  phevents
  phlibraries
  qcorgs
  slthings
  slowners
  tnitems
  tnshops
  aschilds
  asparents
  ccbooks
  ccshops
  ccteams
  deleteowners
  destroyowners
  nullifyowners
  onedestroyowners
  onenullifyowners
  onerestexcowners
  resterrowners
  restexcowners
  singletons
  thusers
  phusers
  users
>;

sub clean-shared-tables is export {
  my $adapter = DB.shared.adapter;
  return unless $adapter.defined && $adapter.is-connected;
  my %present = $adapter.get-table-names.list.map(* => True);
  for @SHARED-TABLE-CLEAN-ORDER -> $t {
    next unless %present{$t};
    try $adapter.exec("DELETE FROM $t");
  }
}
