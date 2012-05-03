------------------------------------------------------
-- Temporal schema for an example "countries" relation
--
-- http://github.com/ifad/chronomodel
--
create schema temporal; -- schema containing all temporal tables
create schema history;  -- schema containing all history tables

-- Current countries data - nothing special
--
create table temporal.countries (
  id   serial primary key,
  name varchar
);

-- Countries historical data.
--
-- Inheritance is used to avoid duplicating the schema from the main table.
-- Please note that columns on the main table cannot be dropped, and other caveats
-- http://www.postgresql.org/docs/9.0/static/ddl-inherit.html#DDL-INHERIT-CAVEATS
--
create table history.countries (

  hid         serial primary key,
  valid_from  timestamp not null,
  valid_to    timestamp not null default '9999-12-31',
  recorded_at timestamp not null default now(),

  constraint from_before_to check (valid_from < valid_to),

  constraint overlapping_times exclude using gist (
    box(
      point( extract( epoch from valid_from), id ),
      point( extract( epoch from valid_to - interval '1 millisecond'), id )
    ) with &&
  )
) inherits ( temporal.countries );

create index timestamps on history.countries using btree ( valid_from, valid_to ) with ( fillfactor = 100 );
create index country_id on history.countries using btree ( id ) with ( fillfactor = 90 );

-- The countries view, what the Rails' application ORM will actually CRUD on, and
-- the core of the temporal updates.
--
-- SELECT - return only current data
--
create view public.countries as select * from only temporal.countries;

-- INSERT - insert data both in the current data table and in the history table.
-- Return data from the history table as the RETURNING clause must be the last
-- one in the rule.
create rule countries_ins as on insert to public.countries do instead (
  insert into temporal.countries ( name ) values ( new.name );

  insert into history.countries ( id, name, valid_from )
    values ( currval('temporal.countries_id_seq'), new.name, now() )
    returning ( new.name )
);

-- UPDATE - set the last history entry validity to now, save the current data in
-- a new history entry and update the current table with the new data.
--
create rule countries_upd as on update to countries do instead (
  update history.countries
    set   valid_to = now()
    where id       = old.id and valid_to = '9999-12-31';

  insert into history.countries ( id, name, valid_from ) 
  values ( old.id, new.name, now() );

  update only temporal.countries
    set name = new.name
    where id = old.id
);

-- DELETE - save the current data in the history and eventually delete the data
-- from the current table.
--
create rule countries_del as on delete to countries do instead (
  update history.countries
    set   valid_to = now()
    where id       = old.id and valid_to = '9999-12-31';

  delete from only temporal.countries
  where temporal.countries.id = old.id
);

-- EOF
