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
      point( date_part( 'epoch', valid_from), id ),
      point( date_part( 'epoch', valid_to - interval '1 millisecond'), id )
    ) with &&
  )
) inherits ( temporal.countries );

-- Inherited primary key
create index country_inherit_pkey on history.countries ( id )

-- Snapshot of data at a specific point in time
create index country_snapshot on history.countries USING gist (
  box(
    point( date_part( 'epoch', valid_from ), 0 ),
    point( date_part( 'epoch', valid_to   ), 0 )
  )
)

-- Used by the rules queries when UPDATE'ing and DELETE'ing
create index country_valid_from  on history.countries ( valid_from )
create index country_valid_to    on history.countries ( valid_from )
create index country_recorded_at on history.countries ( id, valid_to )

-- Single instance whole history
create index country_instance_history on history.countries ( id, recorded_at )


-- The countries view, what the Rails' application ORM will actually CRUD on, and
-- the core of the temporal updates.
--
-- SELECT - return only current data
--
create view public.countries as select *, xmin as __xid from only temporal.countries;

-- INSERT - insert data both in the current data table and in the history table.
--
-- A trigger is required if there is a serial ID column, as rules by
-- design cannot handle the following case:
--
--   * INSERT INTO ... SELECT: if using currval(), all the rows
--     inserted in the history will have the same identity value;
--
--   * if using a separate sequence to solve the above case, it may go
--     out of sync with the main one if an INSERT statement fails due
--     to a table constraint (the first one is nextval()'ed but the
--     nextval() on the history one never happens)
--
-- So, only for this case, we resort to an AFTER INSERT FOR EACH ROW trigger.
--
-- Ref: GH Issue #4.
--
create rule countries_ins as on insert to public.countries do instead (

  insert into temporal.countries ( name ) values ( new.name );
  returning ( id, new.name, xmin )
);

create or replace function temporal.countries_ins() returns trigger as $$
  begin
    insert into history.countries ( id, name, valid_from )
    values ( currval('temporal.countries_id_seq'), new.name, timezone('utc', now()) );
    return null;
  end;
$$ language plpgsql;

create trigger history_ins after insert on temporal.countries_ins()
  for each row execute procedure temporal.countries_ins();

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
