# ChronoModel

A temporal database system on PostgreSQL using
[table inheritance](http://www.postgresql.org/docs/9.0/static/ddl-inherit.html) and
[the rule system](http://www.postgresql.org/docs/9.0/static/rules-update.html).

This is a data structure for a
[Slowly-Changing Dimension Type 2](http://en.wikipedia.org/wiki/Slowly_changing_dimension#Type_2)
temporal database, implemented using only [PostgreSQL](http://www.postgresql.org) >= 9.0 features.

All the history recording is done inside the database system, freeing the application code from
having to deal with it.

The application model is backed by an updatable view that behaves exactly like a plain table, while
behind the scenes the database redirects the queries to concrete tables using
[the rule system](http://www.postgresql.org/docs/9.0/static/rules-update.html).

Current data is hold in a table in the `current` [schema](http://www.postgresql.org/docs/9.0/static/ddl-schemas.html),
while history in hold in another table in the `history` schema. The latter
[inherits](http://www.postgresql.org/docs/9.0/static/ddl-inherit.html) from the former, to get
automated schema updates for free. Partitioning of history is even possible but not implemented
yet.

The updatable view is created in the default `public` schema, making it visible to Active Record.

All Active Record schema migration statements are decorated with code that handles the temporal
structure by e.g. keeping the view rules in sync or dropping/recreating it when required by your
migrations. A schema dumper is available as well.

Data extraction at a single point in time and even `JOIN`s between temporal and non-temporal data
is implemented using
[Common Table Expressions](http://www.postgresql.org/docs/9.0/static/queries-with.html)
(WITH queries) and a `WHERE date >= valid_from AND date < valid_to` clause, generated automatically
by the provided `TimeMachine` module to be included in your models.

Optimal temporal timestamps indexing is provided for both PostgreSQL 9.0 and 9.1 query planners.

All timestamps are (forcibly) stored in the UTC time zone, bypassing the `AR::Base.config.default_timezone`
setting.

See  [README.sql](https://github.com/ifad/chronomodel/blob/master/README.sql) for the plain SQL
defining this temporal schema for a single table.


## Requirements

* Ruby &gt;= 1.9.2
* Active Record &gt;= 3.2
* PostgreSQL &gt;= 9.0


## Installation

Add this line to your application's Gemfile:

    gem 'chrono_model', :git => 'git://github.com/ifad/chronomodel'

And then execute:

    $ bundle


## Schema creation

This library hooks all `ActiveRecord::Migration` methods to make them temporal aware.

The only option added is `:temporal => true` to `create_table`:

    create_table :countries, :temporal => true do |t|
      t.string :common_name
      t.references :currency
      # ...
    end

That'll create the _current_, its _history_ child table and the _public_ view.
Every other housekeeping of the temporal structure is handled behind the scenes
by the other schema statements. E.g.:

 * `rename_table`  - renames tables, views, sequences, indexes and rules
 * `drop_table`    - drops the temporal table and all dependant objects
 * `add_column`    - adds the column to the current table and updates rules
 * `rename_column` - renames the current table column and updates the rules
 * `remove_column` - removes the current table column and updates the rules
 * `add_index`     - creates the index in the history table as well
 * `remove_index`  - removes the index from the history table as well


## Adding Temporal extensions to an existing table

Use `change_table`:

    change_table :your_table, :temporal => true

If you want to also set up the history from your current data:

    change_table :your_table, :temporal => true, :copy_data => true

This will create an history record for each record in your table, setting its
validity from midnight, January 1st, 1 CE. You can set a specific validity
with the `:validity` option:

    change_table :your_table, :temporal => true, :copy_data => true, :validity => '1977-01-01'


## Data querying

A model backed by a temporal view will behave like any other model backed by a
plain table. If you want to do as-of-date queries, you need to include the
`ChronoModel::TimeMachine` module in your model.

    module Country < ActiveRecord::Base
      include ChronoModel::TimeMachine

      has_many :compositions
    end

This will create a `Country::History` model inherited from `Country`, and it
will make an `as_of` class method available to your model. E.g.:

    Country.as_of(1.year.ago)

Will execute:

    WITH countries AS (
      SELECT * FROM history.countries WHERE #{1.year.ago.utc} >= valid_from AND #{1.year.ago.utc} < valid_to
    ) SELECT * FROM countries

This work on associations using temporal extensions as well:

    Country.as_of(1.year.ago).first.compositions

Will execute:

    WITH countries AS (
      SELECT * FROM history.countries WHERE #{1.year.ago.utc} >= valid_from AND #{1.year.ago.utc} < valid_to
    ) SELECT * FROM countries LIMIT 1

    WITH compositions AS (
      SELECT * FROM history.countries WHERE #{above_timestamp} >= valid_from AND #{above_timestamp} < valid_to
    ) SELECT * FROM compositions WHERE country_id = X
    
And `.joins` works as well:

    Country.as_of(1.month.ago).joins(:compositions)
    
Will execute:

    WITH countries AS (
      SELECT * FROM history.countries WHERE #{1.year.ago.utc} >= valid_from AND #{1.year.ago.utc} < valid_to
    ), compositions AS (
      SELECT * FROM history.countries WHERE #{above_timestamp} >= valid_from AND #{above_timestamp} < valid_to
    ) SELECT * FROM countries INNER JOIN countries ON compositions.country_id = countries.id

More methods are provided, see the
[TimeMachine](https://github.com/ifad/chronomodel/blob/master/lib/chrono_model/time_machine.rb) source
for more information.


## Running tests

You need a running Postgresql instance. Create `spec/config.yml` with the
connection authentication details (use `spec/config.yml.example` as template).

Run `rake`. SQL queries are logged to `spec/debug.log`. If you want to see
them in your output, use `rake VERBOSE=true`.

## Caveats

 * `.includes` still doesn't work, but it'll fixed soon.

 * Some monkeypatching has been necessary both to `ActiveRecord::Relation` and
   to `Arel::Visitors::ToSql` to fix a bug with `WITH` queries generation. This
   will be reported to the upstream with a pull request after extensive testing.

 * The migration statements extension is implemented using a Man-in-the-middle
   class that inherits from the PostgreSQL adapter, and that relies on some
   private APIs. This should be made more maintainable, maybe by implementing
   an extension framework for connection adapters. This library will (clearly)
   never be merged into Rails, as it is against its principle of treating the
   SQL database as a dummy data store.

 * The schema dumper is WAY TOO hacky.

 * Savepoints are disabled, because there is
   [currently](http://archives.postgresql.org/pgsql-hackers/2012-08/msg01094.php)
   no way to identify a subtransaction belonging to the current transaction.


## Contributing

 1. Fork it
 2. Create your feature branch (`git checkout -b my-new-feature`)
 3. Commit your changes (`git commit -am 'Added some feature'`)
 4. Push to the branch (`git push origin my-new-feature`)
 5. Create new Pull Request
