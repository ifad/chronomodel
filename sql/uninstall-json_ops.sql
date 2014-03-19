DO $$
  BEGIN

    DROP OPERATOR CLASS json_ops using hash;
    RAISE LOG 'Dropped JSON hash operator class';

  EXCEPTION WHEN undefined_object THEN
    RAISE NOTICE 'JSON hash operator class does not exist, skipping';
  END;
$$ LANGUAGE plpgsql;

DO $$
  BEGIN

    DROP OPERATOR = ( json, json );
    RAISE LOG 'Dropped JSON equality operator';

  EXCEPTION WHEN undefined_function THEN
    RAISE NOTICE 'JSON equality operator does not exist, skipping';
  END;
$$ LANGUAGE plpgsql;

DROP FUNCTION IF EXISTS json_eq( json, json );
DROP FUNCTION IF EXISTS json_hash ( json );
