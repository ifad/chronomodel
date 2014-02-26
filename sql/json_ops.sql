-- This is a naive, unoptimized way of checking two
-- JSON objects for equality. It uses python's json
-- module to load and re-dump the json object while
-- sorting its keys, and then calculates the object
-- hash from it.
--
CREATE OR REPLACE FUNCTION json_hash( a json ) RETURNS INT8 AS $$
  import json
  return hash(json.dumps(json.loads(a), sort_keys=True, separators=(',', ':')))
$$ LANGUAGE plpythonu STRICT IMMUTABLE;

CREATE OR REPLACE FUNCTION json_eq( a json, b json ) RETURNS BOOLEAN AS $$
  SELECT json_hash(a) = json_hash(b);
$$ LANGUAGE SQL STRICT IMMUTABLE;

CREATE OPERATOR = (
  LEFTARG   = json,
  RIGHTARG  = json,
  PROCEDURE = json_eq
);

CREATE OPERATOR CLASS json_ops
DEFAULT FOR TYPE JSON USING hash AS
OPERATOR    1   =  (json, json),
FUNCTION    1   json_hash(json);
