-- This is a naive, unoptimized way of checking two
-- JSON objects for equality. It uses python's json
-- module to load and re-dump the json object while
-- sorting its keys, and then calculates the object
-- hash from it.
--
CREATE OR REPLACE FUNCTION json_hash( a json ) RETURNS INTEGER AS $$
  import json

  # http://www.isthe.com/chongo/tech/comp/fnv/#FNV-1a
  def fnv1a(str):
    hval = 2166136261
    for s in str:
      hval = hval ^ ord(s)
      hval = (hval * 16777619) % (2**32)
    return hval

  hsh = fnv1a(json.dumps(json.loads(a), sort_keys=True, separators=(',', ':')))
  return hsh - 2**31

$$ LANGUAGE plpythonu STRICT IMMUTABLE;

CREATE OR REPLACE FUNCTION json_eq( a json, b json ) RETURNS BOOLEAN AS $$
  SELECT json_hash(a) = json_hash(b);
$$ LANGUAGE SQL STRICT IMMUTABLE;

DO $$
  BEGIN

    CREATE OPERATOR = (
      LEFTARG   = json,
      RIGHTARG  = json,
      PROCEDURE = json_eq
    );

    RAISE LOG 'Created JSON equality operator';

  EXCEPTION WHEN duplicate_function THEN
    RAISE NOTICE 'JSON equality operator already exists, skipping';
  END;
$$ LANGUAGE plpgsql;

DO $$
  BEGIN

    CREATE OPERATOR CLASS json_ops
    DEFAULT FOR TYPE JSON USING hash AS
    OPERATOR    1   =  (json, json),
    FUNCTION    1   json_hash(json);

    RAISE LOG 'Created JSON hash operator class';

  EXCEPTION WHEN duplicate_object THEN
    RAISE NOTICE 'JSON hash operator class already exists, skipping';
  END;
$$ LANGUAGE plpgsql;
