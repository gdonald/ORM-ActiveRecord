
use ORM::ActiveRecord::Schema::Field;
use ORM::ActiveRecord::DB;
use ORM::ActiveRecord::Support::Environment;
use ORM::ActiveRecord::Support::Utils;
use ORM::ActiveRecord::Relation::Query::Conditions;
use ORM::ActiveRecord::Relation::Query::Modifiers;
use ORM::ActiveRecord::Relation::Query::Joins;
use ORM::ActiveRecord::Relation::Query::Sql;
use ORM::ActiveRecord::Relation::Query::Predicates;
use ORM::ActiveRecord::Relation::Query::Aggregations;
use ORM::ActiveRecord::Relation::Query::Finders;
use ORM::ActiveRecord::Relation::Query::Bulk;
use ORM::ActiveRecord::Relation::Query::Batching;
use ORM::ActiveRecord::Relation::Query::Preloader;

class Query
does QueryConditions
does QueryModifiers
does QueryJoins
does QuerySql
does QueryPredicates
does QueryAggregations
does QueryFinders
does QueryBulk
does QueryBatching
does QueryPreloader
is export
{
  has Mu $!class;
  has Str $!table;
  has Hash $!params;
  has Hash $!not-params;
  has @!or-relations;
  has @!fields of Field;
  has @!order;
  has Int $!limit  = 0;
  has Int $!offset = 0;
  has @!select;
  has Bool $!distinct = False;
  has @!group;
  has @!having;
  has Str $!from-source;
  has Str $!from-alias;
  has @!references;
  has Bool $!readonly = False;
  has @!joins;
  has Bool $!is-none = False;
  has Hash $!create-with-attrs = {};
  has @!ctes;
  has @!annotations;
  has @!optimizer-hints;
  has $!lock = False;
  has @!preloads;
  has @!eager-loads;
  has @!pending-includes;

  submethod BUILD(Mu:U :$!class, Hash:D :$params) {
    $!table = Utils.table-name($!class);
    $!params = {};
    $!not-params = {};
    @!fields = self.db.get-fields(:$!table).map({ Field.new(:name($_[0]), :type($_[1])) });
    for self!normalize-assoc-params($params).kv -> $k, $v { $!params{$k} = $v }
    self!apply-sti-default-scope;
  }

  # A subclass finder restricts to its own STI type values; the base sees all
  # rows. A user-supplied filter on the inheritance column takes precedence.
  method !apply-sti-default-scope {
    return unless $!class.^can('sti-active');
    $!class.register-sti;
    return unless $!class.sti-active && !$!class.descends-from-active-record;

    my $column = $!class.inheritance-column;
    return if $!params{$column}:exists;
    $!params{$column} = $!class.sti-scope-names;
  }

  method where-values           is rw { $!params }
  method where-not-values       is rw { $!not-params }
  method or-relations           is rw { @!or-relations }
  method order-values           is rw { @!order }
  method limit-value            is rw { $!limit }
  method offset-value           is rw { $!offset }
  method select-values          is rw { @!select }
  method distinct-value         is rw { $!distinct }
  method group-values           is rw { @!group }
  method having-values          is rw { @!having }
  method from-source            is rw { $!from-source }
  method from-alias             is rw { $!from-alias }
  method references-values      is rw { @!references }
  method readonly-value         is rw { $!readonly }
  method joins-values           is rw { @!joins }
  method is-none-value          is rw { $!is-none }
  method create-with-attrs      is rw { $!create-with-attrs }
  method ctes-values            is rw { @!ctes }
  method annotations-values     is rw { @!annotations }
  method optimizer-hints-values is rw { @!optimizer-hints }
  method lock-value             is rw { $!lock }
  method preloads-values        is rw { @!preloads }
  method eager-loads-values     is rw { @!eager-loads }
  method pending-includes-values is rw { @!pending-includes }
  method class-of               { $!class }
  method table-of               { $!table }

  method db(--> DB) {
    my $name = $!class.^can('connection-name') ?? $!class.connection-name !! default-connection();
    DB.shared(name => $name);
  }

  method fields-of              { @!fields }

  method clone-query(--> Query) {
    my $copy = Query.new(:class($!class), :params({}));
    $copy!load-from(self);
    $copy;
  }

  method !load-from(Query:D $src) {
    $!params            = $src.where-values.clone;
    $!not-params        = $src.where-not-values.clone;
    @!or-relations      = $src.or-relations.clone;
    @!order             = $src.order-values.clone;
    $!limit             = $src.limit-value;
    $!offset            = $src.offset-value;
    @!select            = $src.select-values.clone;
    $!distinct          = $src.distinct-value;
    @!group             = $src.group-values.clone;
    @!having            = $src.having-values.clone;
    $!from-source       = $src.from-source;
    $!from-alias        = $src.from-alias;
    @!references        = $src.references-values.clone;
    $!readonly          = $src.readonly-value;
    @!joins             = $src.joins-values.clone;
    $!is-none           = $src.is-none-value;
    $!create-with-attrs = $src.create-with-attrs.clone;
    @!ctes              = $src.ctes-values.clone;
    @!annotations       = $src.annotations-values.clone;
    @!optimizer-hints   = $src.optimizer-hints-values.clone;
    $!lock              = $src.lock-value;
    @!preloads          = $src.preloads-values.clone;
    @!eager-loads       = $src.eager-loads-values.clone;
    @!pending-includes  = $src.pending-includes-values.clone;
  }
}
