# ChronoModel

A temporal database system on PostgreSQL using
[table inheritance](http://www.postgresql.org/docs/9.0/static/ddl-inherit.html) and
[the rule system](http://www.postgresql.org/docs/9.0/static/rules-update.html).

This is a data structure for a [Slowly-Changing Dimension Type 2](http://en.wikipedia.org/wiki/Slowly_changing_dimension#Type_2)
temporal database, implemented using only [PostgreSQL](http://www.postgresql.org) >= 9.0 features.

Any application code is completely unaware of the temporal features: queries
are done against an updatable view that behaves exactly like a plain table
while but behind the scenes the database redirects the queries to backend
tables holding actual data, using [the rule system](http://www.postgresql.org/docs/9.0/static/rules-update.html).

Current data is hold in a _current_ table, while history in an _history_ one,
[inheriting](http://www.postgresql.org/docs/9.0/static/ddl-inherit.html) from
the _current_. The two tables are created in two different
[schemas](http://www.postgresql.org/docs/9.0/static/ddl-schemas.html), while
the view is created in the default _public_ schema, so Active Record sees only
it as the table backing your models.

Data extraction at a single point in time and JOINs between temporal and non-temporal
data is implemented using [Common Table Expressions](http://www.postgresql.org/docs/9.0/static/queries-with.html)
(WITH queries) and a `WHERE date BETWEEN valid_from AND valid_to` clause, generated
automatically by the Active Record patches and for which a model API is provided.

All Active Record schema migration statements are decorated with code that
handles the temporal structure by e.g. keeping the view rules in sync or
dropping/recreating it when required by the changes themselves. A schema
dumper is available as well.

Optimal temporal timestamps indexing is provided for both PostgreSQL 9.0 and
9.1 query planners.

See [README.sql](https://github.com/ifad/chronomodel/blob/master/README.sql) file for the plain SQL.


## Requirements

* Active Record >= 3.2
* PostgreSQL >= 9.0


## Installation

Add this line to your application's Gemfile:
    gem 'chronomodel', :git => 'git://github.com/ifad/chronomodel'

And then execute:
    $ bundle


## Migrations

This library hooks the following `ActiveRecord::Migration` methods to make
them temporal aware. Except from passing the `temporal => true` option to
`create_table`, everything else is handled automatically behind the scenes.

 * `create_table :temporal => true` - creates current and history tables,
      indexes, the interface view and the temporal rules
 * `drop_table`    - drops the temporal table and all dependant objects
 * `rename_table`  - renames tables, views, sequences, indexes and rules
 * `add_column`    - adds the column to the current table and updates rules
 * `rename_column` - renames the current table column and updates the rules
 * `remove_column` - removes the current table column and updates the rules
 * `add_index`     - creates the index in the history table as well
 * `remove_index`  - removes the index from the history table as well

## Usage

A model backed by a temporal view will behave like any other model backed by a
plain table. If you want to do as-of-date queries, you need to include the
`ChronoModel::TimeMachine` module in your model.

    module Country < ActiveRecord::Base
      include ChronoModel::TimeMachine

      has_many :compositions
    end

This will make an `as_of` class method available to your model. E.g.:

    Country.as_of(1.year.ago)

Will execute:

    WITH countries AS (
      SELECT * FROM history.countries WHERE #{1.year.ago.to_s(:db)} BETWEEN valid_from AND valid_to
    ) SELECT * FROM countries

This work on associations using temporal extensions as well:

    Country.as_of(1.year.ago).first.compositions

Will execute:

    WITH countries AS (
      SELECT * FROM history.countries WHERE #{1.year.ago.to_s(:db)} BETWEEN valid_from AND valid_to
    ) SELECT * FROM countries LIMIT 1

    WITH compositions AS (
      SELECT * FROM history.countries WHERE -same-timestamp-as-above- BETWEEN valid_from AND valid_to
    ) SELECT * FROM compositions WHERE country_id = X

More documentation to come.


## Contributing

 1. Fork it
 2. Create your feature branch (`git checkout -b my-new-feature`)
 3. Commit your changes (`git commit -am 'Added some feature'`)
 4. Push to the branch (`git push origin my-new-feature`)
 5. Create new Pull Request
