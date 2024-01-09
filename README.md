# Temporal database system on PostgreSQL using [updatable views][pg-updatable-views], [table inheritance][pg-table-inheritance] and [INSTEAD OF triggers][pg-instead-of-triggers].

[![Build Status][build-status-badge]][build-status]
[![Code Climate][code-analysis-badge]][code-analysis]
[![Test Coverage][test-coverage-badge]][test-coverage]
[![Gem Version][gem-version-badge]][gem-version]
[![Inlinedocs][docs-analysis-badge]][docs-analysis]

![A Delorean that we all love][delorean-image]

ChronoModel implements what Oracle sells as "Flashback Queries", with standard
SQL on free PostgreSQL. Academically speaking, ChronoModel implements a
[Type-2 Slowly-Changing Dimension][wp-scd-2] with [history tables][wp-scd-4].

All history keeping happens inside the database system, freeing application
code from having to deal with it. ChronoModel implements all the required
features in Ruby on Rails' ORM to leverage the database temporal structure
beneath.


## Design

The application model is backed by an updatable view in the default `public`
schema that behaves like a plain table to any database client.  When data in
manipulated on it, INSTEAD OF [triggers][pg-triggers] redirect the manipulations
to concrete tables.

*Current* data is held in a table in the `temporal` [schema][pg-schema], while
*History* is held in a table in the `history` schema that [inherits][pg-table-inheritance]
from the *Current* one, to get automated schema updates for free and other
benefits.

The current time is taken using [`current_timestamp`][pg-current-timestamp], so
that multiple data manipulations in the same transaction on the same records
always create a single history entry (they are _squashed_ together).

[Partitioning][pg-partitioning] of history is also possible: this design [fits the
requirements][pg-partitioning-excl-constraints] but it's not implemented yet.

See [README.sql][cm-readme-sql] for a SQL example defining the machinery for a
simple table.


## Active Record integration

All Active Record schema migration statements are decorated with code that
handles the temporal structure by e.g. keeping the triggers in sync or
dropping/recreating it when required by your migrations.

Data extraction at a single point in time and even `JOIN`s between temporal and
non-temporal data is implemented using sub-selects and a `WHERE` generated by
the provided `TimeMachine` module to be included in your models.

The `WHERE` is optimized using [GiST indexes][pg-gist-indexes] on the
`tsrange` defining record validity. Overlapping history is prevented
through [exclusion constraints][pg-exclusion-constraints] and the
[btree_gist][pg-btree-gist] extension.

All timestamps are _forcibly_ stored in as UTC, bypassing the
`default_timezone` setting.


## Requirements

* Ruby >= 3.0
* Active Record >= 7.0. See the [detailed supported versions matrix on Ruby GitHub Actions workflows](https://github.com/ifad/chronomodel/blob/master/.github/workflows)
* PostgreSQL >= 9.4
* The `btree_gist` PostgreSQL extension

With Homebrew:

    brew install postgres

With apt:

    apt-get install postgresql-11

## Installation

Add this line to your application's Gemfile:

    gem 'chrono_model'

And then execute:

    $ bundle


## Configuration

Configure your `config/database.yml` to use the `chronomodel` adapter:

```yaml
development:
  adapter: chronomodel
  username: ...
```

Configure Active Record in your `config/application.rb` to use the `:sql` schema
format:

```rb
config.active_record.schema_format = :sql
```

## Schema creation

ChronoModel hooks all `ActiveRecord::Migration` methods to make them temporal
aware.

```ruby
create_table :countries, temporal: true do |t|
  t.string     :common_name
  t.references :currency
  # ...
end
```

This creates the _temporal_ table, its inherited _history_ one the _public_
view and all the trigger machinery. Every other housekeeping of the temporal
structure is handled behind the scenes by the other schema statements. E.g.:

 * `rename_table`  - renames tables, views, sequences, indexes and triggers
 * `drop_table`    - drops the temporal table and all dependant objects
 * `add_column`    - adds the column to the current table and updates triggers
 * `rename_column` - renames the current table column and updates the triggers
 * `remove_column` - removes the current table column and updates the triggers
 * `add_index`     - creates the index in both _temporal_ and _history_ tables
 * `remove_index`  - removes the index from both tables


## Adding Temporal extensions to an existing table

Use `change_table`:

```ruby
change_table :your_table, temporal: true
```

If you want to also set up the history from your current data:

```ruby
change_table :your_table, temporal: true, copy_data: true
```

This will create an history record for each record in your table, setting its
validity from midnight, January 1st, 1 CE. You can set a specific validity with
the `:validity` option:

```ruby
change_table :your_table, temporal: true, copy_data: true, validity: '1977-01-01'
```

Please note that `change_table` requires you to use *old_style* `up` and
`down` migrations. It cannot work with Rails 3-style `change` migrations.


## Selective Journaling

By default UPDATEs only to the `updated_at` field are not recorded in the
history.

You can also choose which fields are to be journaled, passing the following
options to `create_table`:

  * `journal: %w( fld1 fld2 .. .. )` - record changes in the history only when changing specified fields
  * `no_journal: %w( fld1 fld2 .. )` - do not record changes to the specified fields
  * `full_journal: true`             - record changes to *all* fields, including `updated_at`.

These options are stored as JSON in the [COMMENT][pg-comment] area of the
public view, alongside with the ChronoModel version that created them.

This is visible in `psql` if you issue a `\d+`. Example after a test run:

    chronomodel=# \d+
                                                           List of relations
     Schema |     Name      |   Type   |    Owner    |    Size    |                           Description
    --------+---------------+----------+-------------+------------+-----------------------------------------------------------------
     public | bars          | view     | chronomodel | 0 bytes    | {"temporal":true,"chronomodel":"0.7.0.alpha"}
     public | foos          | view     | chronomodel | 0 bytes    | {"temporal":true,"chronomodel":"0.7.0.alpha"}
     public | plains        | table    | chronomodel | 0 bytes    |
     public | test_table    | view     | chronomodel | 0 bytes    | {"temporal":true,"journal":["foo"],"chronomodel":"0.7.0.alpha"}


## Using Rails Counter Cache

**IMPORTANT**: Rails counter cache issues an UPDATE on the parent record
table, thus triggering new history entries creation. You are **strongly**
advised to NOT journal the counter cache columns, or race conditions will
occur (see https://github.com/ifad/chronomodel/issues/71).

In such cases, ensure to add `no_journal: %w( your_counter_cache_column_name )`
to your `create_table`. Example:

    create_table 'sections', temporal: true, no_journal: %w( articles_count ) do |t|
      t.string :name
      t.integer :articles_count, default: 0
    end

## Data querying

Include the `ChronoModel::TimeMachine` module in your model.

```ruby
class Country < ActiveRecord::Base
  include ChronoModel::TimeMachine

  has_many :compositions
end
```

This will create a `Country::History` model inherited from `Country`, and add
an `as_of` class method.

```ruby
Country.as_of(1.year.ago)
```

Will execute:

```sql
SELECT "countries".* FROM (
  SELECT "history"."countries".* FROM "history"."countries"
  WHERE '#{1.year.ago}' <@ "history"."countries"."validity"
) AS "countries"
```

The returned `ActiveRecord::Relation` will then hold and pass along the
timestamp given to the first `.as_of()` call to queries on associated entities.
E.g.:

```ruby
Country.as_of(1.year.ago).first.compositions
```

Will execute:

```sql
SELECT "countries".*, '#{1.year.ago}' AS as_of_time FROM (
  SELECT "history"."countries".* FROM "history"."countries"
  WHERE '#{1.year.ago}' <@ "history"."countries"."validity"
) AS "countries" LIMIT 1
```

and then, using the above fetched `as_of_time` timestamp, expand to:

```sql
SELECT * FROM  (
  SELECT "history"."compositions".* FROM "history"."compositions"
  WHERE '#{as_of_time}' <@ "history"."compositions"."validity"
) AS "compositions" WHERE country_id = X
```

`.joins` works as well:

```ruby
Country.as_of(1.month.ago).joins(:compositions)
```

Expands to:

```sql
SELECT "countries".* FROM (
  SELECT "history"."countries".* FROM "history"."countries"
  WHERE '#{1.month.ago}' <@ "history"."countries"."validity"
) AS "countries" INNER JOIN (
  SELECT "history"."compositions".* FROM "history"."compositions"
  WHERE '#{1.month.ago}' <@ "history"."compositions"."validity"
) AS "compositions" ON compositions.country_id = countries.id
```

More methods are provided, see the [TimeMachine][cm-timemachine] source for
more information.


## History manipulation

History objects can be changed and `.save`d just like any other record. They
cannot be deleted.

## Upgrading

ChronoModel currently performs upgrades by dropping and re-creating the views
that give access to current data. If you have built other database objects on
these views, the upgrade cannot be performed automatically as the dependant
objects must be dropped first.

When booting, ChronoModel will issue a warning in your logs about the need of
a structure upgrade. Structure usually changes across versions. In this case,
you need to set up a rake task that drops your dependant objects, runs
ChronoModel.upgrade! and then re-creates them.

A migration system should be introduced, but it is seen as overkill for now,
given that usually database objects have creation and dropping scripts.


## Running tests

You need a running PostgreSQL >= 9.4 instance. Create `spec/config.yml` with the
connection authentication details (use `spec/config.yml.example` as template).

You need to connect as  a database superuser, because specs need to create the
`btree_gist` extension.

To run the full test suite, use

    rake

SQL queries are logged to `spec/debug.log`. If you want to see them in your
output, set the `VERBOSE=true` environment variable.

Some tests check the nominal execution of rake tasks within a test Rails app,
and those are quite time consuming. You can run the full ChronoModel tests
only against ActiveRecord by using

    rspec spec/chrono_model

Ensure to run the full test suite before pushing.

## Caveats

 * Considering the nature of modern applications, it's crucial to understand
   that the database time does not necessarily align with the application time
   due to the delay introduced by communication between the application and
   the database server. Consequently, there is no assurance that the application 
   time will always be less than the database time. Therefore, relying solely
   on `created_at` and `updated_at` fields as timestamps to determine the state
   of an object at a specific point in time within the application could
   lead to inaccuracies.

 * Rails 4+ support requires disabling tsrange parsing support, as it
   [is broken][r4-tsrange-broken] and [incomplete][r4-tsrange-incomplete]
   as of now, mainly due to a [design clash with ruby][pg-tsrange-and-ruby].

 * The triggers and temporal indexes cannot be saved in schema.rb. The AR
   schema dumper is quite basic, and it isn't (currently) extensible.
   As we're using many database-specific features, Chronomodel forces the
   usage of the `:sql` schema dumper, and included rake tasks override
   `db:schema:dump` and `db:schema:load` to do `db:structure:dump` and
   `db:structure:load`.
   Two helper tasks are also added, `db:data:dump` and `db:data:load`.

 * The choice of using subqueries instead of [Common Table Expressions][pg-ctes]
   was dictated by the fact that CTEs [currently act as an optimization
   fence][pg-cte-optimization-fence].
   If it will be possible [to opt-out of the fence][pg-cte-opt-out-fence]
   in the future, they will be probably be used again as they were [in the
   past][cm-cte-impl], because the resulting queries were more readable,
   and do not inhibit using `.from()` on the `AR::Relation`.

 * Foreign keys are not supported. [See issue #174][gh-issue-174]

 * There may be unexpected results when combining eager loading and joins.
  [See issue #186][gh-issue-186]

 * Global ID ignores historical objects. [See issue #192][gh-issue-192]

 * Different historical objects are considered the identical. [See issue
   #206][gh-issue-206]


## Contributing

 1. Fork it
 2. Create your feature branch (`git checkout -b my-new-feature`)
 3. Commit your changes (`git commit -am 'Added some great feature'`)
 4. Push to the branch (`git push origin my-new-feature`)
 5. Create new Pull Request


## Special mention

An special mention has to be made to [Paolo Zaccagnini][gh-pzac]
for all his effort in highlighting the improvements and best decisions
taken over the life cycle of the design and implementation of Chronomodel
while using it in many important projects.


## Denominazione d'Origine Controllata

This software is Made in Italy :it: :smile:.


[build-status]: https://github.com/ifad/chronomodel/actions
[build-status-badge]: https://github.com/ifad/chronomodel/actions/workflows/ruby.yml/badge.svg
[code-analysis]: https://codeclimate.com/github/ifad/chronomodel/maintainability
[code-analysis-badge]: https://api.codeclimate.com/v1/badges/cdee7327938dc2eaff99/maintainability
[docs-analysis]: https://inch-ci.org/github/ifad/chronomodel
[docs-analysis-badge]: https://inch-ci.org/github/ifad/chronomodel.svg?branch=master
[gem-version]: https://rubygems.org/gems/chrono_model
[gem-version-badge]: https://badge.fury.io/rb/chrono_model.svg
[test-coverage]: https://codeclimate.com/github/ifad/chronomodel
[test-coverage-badge]: https://codeclimate.com/github/ifad/chronomodel/badges/coverage.svg

[delorean-image]: https://i.imgur.com/DD77F4s.jpg

[wp-scd-2]: https://en.wikipedia.org/wiki/Slowly_changing_dimension#Type_2
[wp-scd-4]: https://en.wikipedia.org/wiki/Slowly_changing_dimension#Type_4

[pg-updatable-views]: https://www.postgresql.org/docs/9.4/sql-createview.html#SQL-CREATEVIEW-UPDATABLE-VIEWS
[pg-table-inheritance]: https://www.postgresql.org/docs/9.4/ddl-inherit.html
[pg-instead-of-triggers]: https://www.postgresql.org/docs/9.4/sql-createtrigger.html
[pg-triggers]: https://www.postgresql.org/docs/9.4/trigger-definition.html
[pg-schema]: https://www.postgresql.org/docs/9.4/ddl-schemas.html
[pg-current-timestamp]: https://www.postgresql.org/docs/9.4/functions-datetime.html#FUNCTIONS-DATETIME-TABLE
[pg-partitioning]: https://www.postgresql.org/docs/9.4/ddl-partitioning.html
[pg-partitioning-excl-constraints]: https://www.postgresql.org/docs/9.4/ddl-partitioning.html#DDL-PARTITIONING-CONSTRAINT-EXCLUSION
[pg-gist-indexes]: https://www.postgresql.org/docs/9.4/gist.html
[pg-exclusion-constraints]: https://www.postgresql.org/docs/9.4/sql-createtable.html#SQL-CREATETABLE-EXCLUDE
[pg-btree-gist]: https://www.postgresql.org/docs/9.4/btree-gist.html
[pg-comment]: https://www.postgresql.org/docs/9.4/sql-comment.html
[pg-tsrange-and-ruby]: https://bugs.ruby-lang.org/issues/6864
[pg-ctes]: https://www.postgresql.org/docs/9.4/queries-with.html
[pg-cte-optimization-fence]: https://www.postgresql.org/message-id/201209191305.44674.db@kavod.com
[pg-cte-opt-out-fence]: https://www.postgresql.org/message-id/CAHyXU0zpM5+Dsb_pKxDmm-ZoWUAt=SkHHaiK_DBqcmtxTas6Nw@mail.gmail.com
[pg-json-type]: https://www.postgresql.org/docs/9.4/datatype-json.html
[pg-json-func]: https://www.postgresql.org/docs/9.4/functions-json.html
[pg-json-opclass]: https://github.com/ifad/chronomodel/blob/master/sql/json_ops.sql

[r4-tsrange-broken]: https://github.com/rails/rails/pull/13793#issuecomment-34608093
[r4-tsrange-incomplete]: https://github.com/rails/rails/issues/14010

[cm-readme-sql]: https://github.com/ifad/chronomodel/blob/master/README.sql
[cm-timemachine]: https://github.com/ifad/chronomodel/blob/master/lib/chrono_model/time_machine.rb
[cm-cte-impl]: https://github.com/ifad/chronomodel/commit/18f4c4b

[gh-pzac]: https://github.com/pzac
[gh-issue-174]: https://github.com/ifad/chronomodel/issues/174
[gh-issue-186]: https://github.com/ifad/chronomodel/issues/186
[gh-issue-192]: https://github.com/ifad/chronomodel/issues/192
[gh-issue-206]: https://github.com/ifad/chronomodel/issues/206
