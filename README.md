# ChronoModel

A temporal database system on PostgreSQL using
[table inheritance](http://www.postgresql.org/docs/9.0/static/ddl-inherit.html) and
[the rule system](http://www.postgresql.org/docs/9.0/static/rules-update.html).

This is a data structure for a [Slowly-Changing Dimension Type 2](http://en.wikipedia.org/wiki/Slowly_changing_dimension#Type_2)
temporal database, implemented using only [PostgreSQL](http://www.postgresql.org) >= 9.0 features.

Any application code is completely unaware of the temporal features: queries
are done against a view that behaves exactly like a plain table (it can be
`SELECT`ed, `UPDATE`d, `INSERT`ed `INTO` and `DELETE`d `FROM`), but behind the
scenes the database redirects the queries to backend tables holding actual
data, using [the rule system](http://www.postgresql.org/docs/9.0/static/rules-update.html).

All data is stored both in a _current_ table and in an _history_ one,
[inheriting](http://www.postgresql.org/docs/9.0/static/ddl-inherit.html) from
the _current_. To query historical data at a given _date_, a `where date
between valid_from and valid_to` clause is enough.

The _current_ and _history_ tables are created in different
[schemas](http://www.postgresql.org/docs/9.0/static/ddl-schemas.html), while
the view is in the default _public_ schema: the application will see only the
view by default.

By changing the [schema search path](http://www.postgresql.org/docs/9.0/static/ddl-schemas.html#DDL-SCHEMAS-PATH)
it is possible to redirect queries to the _history_ tables without changing
the application code, only by adding the aforementioned WHERE clause.
Moreover, this allows to do `JOIN`s between _history_ tables and non-temporal
ones.

Caveat: tre rules must be kept in sync with the schema, and updated if it
changes.

See the README.sql file for the plain SQL.


## Requirements

* Active Record >= 3.0
* PostgreSQL >= 9.0


## Installation

Add this line to your application's Gemfile:
    gem 'chronomodel'

And then execute:
    $ bundle

Or install it yourself as:
    $ gem install chronomodel


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

## Contributing

 1. Fork it
 2. Create your feature branch (`git checkout -b my-new-feature`)
 3. Commit your changes (`git commit -am 'Added some feature'`)
 4. Push to the branch (`git push origin my-new-feature`)
 5. Create new Pull Request
