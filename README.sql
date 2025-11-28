------------------------------------------------------
-- Temporal schema for an example "countries" relation
--
-- https://github.com/ifad/chronomodel
--
create schema temporal; -- schema containing all temporal tables
create schema history;  -- schema containing all history tables

-- Current countries data - nothing special
--
create table temporal.countries (
  id         serial primary key,
  name       varchar,
  updated_at timestamptz
);

-- Countries historical data.
--
-- Inheritance is used to avoid duplicating the schema from the main table.
-- Please note that columns on the main table cannot be dropped, and other caveats
-- https://www.postgresql.org/docs/9.0/ddl-inherit.html#DDL-INHERIT-CAVEATS
--
create table history.countries (
  hid         bigserial primary key,
  validity    tsrange not null,
  recorded_at timestamp not null default timezone('UTC', now())
) inherits ( temporal.countries );

-- Constraint to assure that no more than one record can occupy
-- a definite segment on a timeline.
alter table history.countries add constraint countries_timeline_consistency
  exclude using gist ( id with =, validity with && );

-- Inherited primary key
create index countries_inherit_pkey on history.countries ( id );

-- Snapshot of data at a specific point in time
create index index_countries_temporal_on_validity on history.countries using gist ( validity );

-- Used by the trigger functions when UPDATE'ing and DELETE'ing
create index index_countries_temporal_on_lower_validity on history.countries ( lower(validity) );
create index index_countries_temporal_on_upper_validity on history.countries ( upper(validity) );

-- Recorded at index for ordering
create index countries_recorded_at on history.countries ( recorded_at );

-- Single instance whole history
create index countries_instance_history on history.countries ( id, recorded_at );


-- The countries view, what the Rails' application ORM will actually CRUD on,
-- and the entry point of the temporal triggers.
--
-- SELECT - return only current data
--
create view public.countries as select * from only temporal.countries;

-- INSERT - insert data both in the temporal table and in the history one.
--
-- The serial sequence is invoked manually only if the PK is NULL, to
-- allow setting the PK to a specific value (think migration scenario).
--
create or replace function public.chronomodel_countries_insert() returns trigger as $$
  begin
    if new.id is null then
      new.id := nextval('temporal.countries_id_seq');
    end if;

    insert into temporal.countries ( id, name, updated_at )
    values ( new.id, new.name, new.updated_at );

    insert into history.countries ( id, name, updated_at, validity )
    values ( new.id, new.name, new.updated_at, tsrange(timezone('UTC', now()), null) );

    return new;
  end;
$$ language plpgsql;

drop trigger if exists chronomodel_insert on countries;

create trigger chronomodel_insert
  instead of insert on public.countries
  for each row execute procedure public.chronomodel_countries_insert();

-- UPDATE - set the last history entry validity to now, save the current data
-- in a new history entry and update the temporal table with the new data.
--
-- If there are no changes, this trigger suppresses redundant updates.
--
-- If a row in the history with the current ID and current timestamp already
-- exists, update it with new data. This logic makes possible to "squash"
-- together changes made in a transaction in a single history row.
--
-- By default, history is not recorded if only the updated_at field is changed.
--
create or replace function chronomodel_countries_update() returns trigger as $$
  declare _now timestamp;
  declare _hid integer;
  declare _old record;
  declare _new record;
  begin
    if old is not distinct from new then
      return null;
    end if;

    _old := row(old.name);
    _new := row(new.name);

    if _old is not distinct from _new then
      update only temporal.countries set ( name, updated_at ) = ( new.name, new.updated_at ) where id = old.id;
      return new;
    end if;

    _now := timezone('UTC', now());
    _hid := null;

    select hid into _hid from history.countries where id = old.id and lower(validity) = _now;

    if _hid is not null then
      update history.countries set ( name, updated_at ) = ( new.name, new.updated_at ) where hid = _hid;
    else
      update history.countries set validity = tsrange(lower(validity), _now)
      where id = old.id and upper_inf(validity);

      insert into history.countries ( id, name, updated_at, validity )
      values ( old.id, new.name, new.updated_at, tsrange(_now, null) );
    end if;

    update only temporal.countries set ( name, updated_at ) = ( new.name, new.updated_at ) where id = old.id;

    return new;
  end;
$$ language plpgsql;

drop trigger if exists chronomodel_update on countries;

create trigger chronomodel_update
  instead of update on temporal.countries
  for each row execute procedure chronomodel_countries_update();

-- DELETE - save the current data in the history and eventually delete the
-- data from the temporal table.
--
-- The first DELETE is required to remove history for records INSERTed and
-- DELETEd in the same transaction.
--
create or replace function chronomodel_countries_delete() returns trigger as $$
  declare _now timestamp;
  begin
    _now := timezone('UTC', now());

    delete from history.countries
    where id = old.id and validity = tsrange(_now, null);

    update history.countries set validity = tsrange(lower(validity), _now)
    where id = old.id and upper_inf(validity);

    delete from only temporal.countries
    where temporal.id = old.id;

    return old;
  end;
$$ language plpgsql;

drop trigger if exists chronomodel_delete on countries;

create trigger chronomodel_delete
  instead of delete on temporal.countries
  for each row execute procedure chronomodel_countries_delete();

-- EOF
