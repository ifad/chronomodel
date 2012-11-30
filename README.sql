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
  recorded_at timestamp not null default timezone('UTC', now()),

  constraint from_before_to check (valid_from < valid_to),

  constraint overlapping_times exclude using gist (
    box(
      point( extract( epoch from valid_from), id ),
      point( extract( epoch from valid_to - interval '1 millisecond'), id )
    ) with &&
  )
) inherits ( temporal.countries );

-- Inherited primary key
create index country_inherit_pkey ON countries ( id )

-- Snapshot of all entities at a specific point in time
create index country_snapshot          on history.countries ( valid_from, valid_to )

-- Snapshot of a single entity at a specific point in time
create index country_instance_snapshot on history.countries ( id, valid_from, valid_to )

-- History update
create index country_instance_update   on history.countries ( id, valid_to )

-- Single instance whole history
create index country_instance_history  on history.countries ( id, recorded_at )


-- The countries view, what the Rails' application ORM will actually CRUD on, and
-- the core of the temporal updates.
--
-- SELECT - return only current data
--
create view public.countries as select *, xmin as __xid from only temporal.countries;

-- INSERT - insert data both in the current data table and in the history table.
-- Return data from the history table as the RETURNING clause must be the last
-- one in the rule.
--
-- A separate sequence is used to keep the primary keys in the history in sync
-- with the temporal table, instead of using currval(), because when using INSERT
-- INTO .. SELECT, currval() returns the value of the last inserted row - while
-- nextval() gets expanded by the rule system for each row to be inserted.
--
-- For this example, it is assumed that the countries_id_seq sequence is at the
-- current value of "420" and it increments by "1".
--
-- Ref: GH Issue #4.
--
create rule countries_ins as on insert to public.countries do instead (
  create sequence history.countries_id_seq start with 420 increment by 1;

  insert into temporal.countries ( name ) values ( new.name );

  insert into history.countries ( id, name, valid_from )
    values ( nextval('history.countries_id_seq'), new.name, timezone('UTC', now()) )
    returning ( id, new.name, xmin )
);

-- UPDATE - set the last history entry validity to now, save the current data in
-- a new history entry and update the current table with the new data.
-- In transactions, create the new history entry only on the first statement,
-- and update the history instead on subsequent ones.
--
create rule countries_upd_first as on update to countries
where old.__xid::char(10)::int8 <> (txid_current() & (2^32-1)::int8)
do instead (
  update history.countries
     set valid_to = timezone('UTC', now())
   where id = old.id and valid_to = '9999-12-31';

  insert into history.countries ( id, name, valid_from ) 
  values ( old.id, new.name, timezone('UTC', now()) );

  update only temporal.countries
     set name = new.name
   where id = old.id
);
create rule countries_upd_next as on update to countries do instead (
  update history.countries
     set name = new.name
   where id = old.id and valid_from = timezone('UTC', now())

  update only temporal.countries
     set name = new.name
   where id = old.id
)

-- DELETE - save the current data in the history and eventually delete the data
-- from the current table. Special case for records INSERTed and DELETEd in the
-- same transaction - they won't appear at all in history.
--
create rule countries_del as on delete to countries do instead (
  delete from history.countries
   where id = old.id
     and valid_from = timezone('UTC', now())
     and valid_to   = '9999-12-31'

  update history.countries
    set   valid_to = now()
    where id = old.id and valid_to = '9999-12-31';

  delete from only temporal.countries
  where temporal.countries.id = old.id
);

-- EOF
