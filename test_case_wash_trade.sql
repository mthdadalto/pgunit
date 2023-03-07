CREATE OR REPLACE PROCEDURE pgunit.test_case_wash_trade_same_from_to_existing(
	)
LANGUAGE 'plpgsql'
AS $BODY$
declare
  _event RECORD;
begin

    SELECT ae.*, a.name, a.token_id
    FROM asset_event ae 
    LEFT JOIN asset a ON a.id = ae.asset_id
    WHERE
        ae.event_hash = '0xa6006bf073cadd4c809e85f2bb5347b3d9c262ef18e18ec1bd589b21e4d343fd' -- same-from-to
    LIMIT 1
    INTO _event;

    CREATE TEMP TABLE tmp_events AS SELECT * FROM wash_trade(_event, true);

    perform pgunit.assertNotNull('event does not exists', _event);
    perform pgunit.assertTrue('number of events should be 1', (SELECT COUNT(*) FROM tmp_events) = 1);

    DROP TABLE tmp_events;

end;
$BODY$;
ALTER PROCEDURE pgunit.test_case_wash_trade_same_from_to_existing()
    OWNER TO ebl_staging_o;

-----------------------------------------------------------------------------------------------

CREATE OR REPLACE PROCEDURE pgunit.test_case_wash_trade_same_from_to_non_existing(
	)
LANGUAGE 'plpgsql'
AS $BODY$
declare
  _event RECORD;
begin

    SELECT ae.*, a.name, a.token_id
    FROM asset_event ae 
    LEFT JOIN asset a ON a.id = ae.asset_id
    WHERE
        ae.to_address != ae.from_address -- same-from-to
    LIMIT 1
    INTO _event;

    CREATE TEMP TABLE tmp_events AS SELECT * FROM wash_trade(_event, true);

    perform pgunit.assertNotNull('event does not exists', _event);
    perform pgunit.assertTrue('number of events should NOT be 1', (SELECT COUNT(*) FROM tmp_events) != 1);

    DROP TABLE tmp_events;

end;
$BODY$;
ALTER PROCEDURE pgunit.test_case_wash_trade_same_from_to_non_existing()
    OWNER TO ebl_staging_o;

-----------------------------------------------------------------------------------------------

CREATE OR REPLACE PROCEDURE pgunit.test_case_wash_trade_ping_pong_existing(
	)
LANGUAGE 'plpgsql'
AS $BODY$
declare
  _event RECORD;
begin

    SELECT ae.*, a.name, a.token_id
    FROM asset_event ae 
    LEFT JOIN asset a ON a.id = ae.asset_id
    WHERE
        ae.event_hash = '0x03d1d3d11d7765c08353f46ccc13f9addf28ded0c986d61804cd20f5af2be54d' -- ping-pong
    LIMIT 1
    INTO _event;

    CREATE TEMP TABLE tmp_events AS SELECT * FROM wash_trade(_event, true);

    perform pgunit.assertNotNull('event does not exists', _event);
    perform pgunit.assertTrue('number of events should be 1', (SELECT COUNT(*) FROM tmp_events) = 2);

    DROP TABLE tmp_events;

end;
$BODY$;
ALTER PROCEDURE pgunit.test_case_wash_trade_ping_pong_existing()
    OWNER TO ebl_staging_o;
    
-----------------------------------------------------------------------------------------------

CREATE OR REPLACE PROCEDURE pgunit.test_case_wash_trade_ping_pong_not_existing(
	)
LANGUAGE 'plpgsql'
AS $BODY$
declare
  _event RECORD;
begin

    SELECT ae.*, a.name, a.token_id
    FROM asset_event ae 
    LEFT JOIN asset a ON a.id = ae.asset_id
    WHERE
		-- a same-from-to hash to false test
        ae.event_hash = '0xa6006bf073cadd4c809e85f2bb5347b3d9c262ef18e18ec1bd589b21e4d343fd' -- ping-pong
    LIMIT 1
    INTO _event;

    CREATE TEMP TABLE tmp_events AS SELECT * FROM wash_trade(_event, true);

    perform pgunit.assertNotNull('event does not exists', _event);
    perform pgunit.assertTrue('number of events should be 1', (SELECT COUNT(*) FROM tmp_events) != 2);

    DROP TABLE tmp_events;

end;
$BODY$;
ALTER PROCEDURE pgunit.test_case_wash_trade_ping_pong_not_existing()
    OWNER TO ebl_staging_o;

-----------------------------------------------------------------------------------------------

CREATE OR REPLACE PROCEDURE pgunit.test_case_wash_trade_very_active_existing(
	)
LANGUAGE 'plpgsql'
AS $BODY$
declare
  _event RECORD;
begin

    SELECT ae.*, a.name, a.token_id
    FROM asset_event ae 
    LEFT JOIN asset a ON a.id = ae.asset_id
    WHERE
		ae.event_hash = '0xd7f9232f45492f814bf6e7682d98ca115369cbbff11f9fc8792ebfb5a9cb1a72' -- very-active
    LIMIT 1
    INTO _event;

    CREATE TEMP TABLE tmp_events AS SELECT * FROM wash_trade(_event, true);

    perform pgunit.assertNotNull('event does not exists', _event);
    perform pgunit.assertTrue('number of events should be 1', (SELECT COUNT(*) FROM tmp_events) > 9 );

    DROP TABLE tmp_events;

end;
$BODY$;
ALTER PROCEDURE pgunit.test_case_wash_trade_very_active_existing()
    OWNER TO ebl_staging_o;
    
-----------------------------------------------------------------------------------------------

CREATE OR REPLACE PROCEDURE pgunit.test_case_wash_trade_very_active_not_existing(
	)
LANGUAGE 'plpgsql'
AS $BODY$
declare
  _event RECORD;
begin

    SELECT ae.*, a.name, a.token_id
    FROM asset_event ae 
    LEFT JOIN asset a ON a.id = ae.asset_id
    WHERE
		-- a ping-pong hash to false test
        ae.event_hash = '0x03d1d3d11d7765c08353f46ccc13f9addf28ded0c986d61804cd20f5af2be54d'
    LIMIT 1
    INTO _event;

    CREATE TEMP TABLE tmp_events AS SELECT * FROM wash_trade(_event, true);

    perform pgunit.assertNotNull('event does not exists', _event);
    perform pgunit.assertTrue('number of events should be 1', (SELECT COUNT(*) FROM tmp_events) < 9);

    DROP TABLE tmp_events;

end;
$BODY$;
ALTER PROCEDURE pgunit.test_case_wash_trade_very_active_not_existing()
    OWNER TO ebl_staging_o;

-----------------------------------------------------------------------------------------------

CREATE OR REPLACE PROCEDURE pgunit.test_case_wash_trade_bunched_existing(
	)
LANGUAGE 'plpgsql'
AS $BODY$
declare
  _event RECORD;
  _count INT;
begin

    SELECT ae.*, a.name, a.token_id
    FROM asset_event ae 
    LEFT JOIN asset a ON a.id = ae.asset_id
    WHERE
        ae.event_hash = '0xc82a860e2470100edde8f38521b5a4119bc54908c56d0766c0e92be9b68c99ca'
    LIMIT 1
    INTO _event;

    CREATE TEMP TABLE tmp_events AS SELECT * FROM wash_trade(_event, true);

    SELECT COUNT(*) 
    FROM tmp_events 
    CROSS JOIN LATERAL jsonb_object_keys(reason) AS first_key
    WHERE first_key like 'bunched-transactions' 
    INTO _count;

    perform pgunit.assertNotNull('event does not exists', _event);
    perform pgunit.assertTrue('number of bunched events should be at least 1', _count > 0);

    DROP TABLE tmp_events;

end;
$BODY$;
ALTER PROCEDURE pgunit.test_case_wash_trade_bunched_existing()
    OWNER TO ebl_staging_o;

-----------------------------------------------------------------------------------------------

CREATE OR REPLACE PROCEDURE pgunit.test_case_wash_trade_bunched_not_existing(
	)
LANGUAGE 'plpgsql'
AS $BODY$
declare
  _event RECORD;
  _count INT;
begin

    SELECT ae.*, a.name, a.token_id
    FROM asset_event ae 
    LEFT JOIN asset a ON a.id = ae.asset_id
    WHERE
		-- a ping-pong hash to false test
        ae.event_hash = '0x03d1d3d11d7765c08353f46ccc13f9addf28ded0c986d61804cd20f5af2be54d'
    LIMIT 1
    INTO _event;

    CREATE TEMP TABLE tmp_events AS SELECT * FROM wash_trade(_event, true);

    SELECT COUNT(*) 
    FROM tmp_events 
    CROSS JOIN LATERAL jsonb_object_keys(reason) AS first_key
    WHERE first_key like 'bunched-transactions' 
    INTO _count;

    perform pgunit.assertNotNull('event does not exists', _event);
    perform pgunit.assertTrue('number of events should NOT be higher than 0', _count < 1);

    DROP TABLE tmp_events;

end;
$BODY$;
ALTER PROCEDURE pgunit.test_case_wash_trade_bunched_not_existing()
    OWNER TO ebl_staging_o;

-- PROCEDURE: pgunit.test_case_wash_trade_bunched_existing_fail()

-- DROP PROCEDURE IF EXISTS pgunit.test_case_wash_trade_bunched_existing_fail();

CREATE OR REPLACE PROCEDURE pgunit.test_case_wash_trade_bunched_existing_fail(
	)
LANGUAGE 'plpgsql'
AS $BODY$
declare
  _event RECORD;
  _count INT;
begin

    SELECT ae.*, a.name, a.token_id
    FROM asset_event ae 
    LEFT JOIN asset a ON a.id = ae.asset_id
    WHERE
		--wrong event
        ae.event_hash = '0x03d1d3d11d7765c08353f46ccc13f9addf28ded0c986d61804cd20f5af2be54d'
    LIMIT 1
    INTO _event;

    CREATE TEMP TABLE tmp_events AS SELECT * FROM wash_trade(_event, true);

    SELECT COUNT(*) 
    FROM tmp_events 
    CROSS JOIN LATERAL jsonb_object_keys(reason) AS first_key
    WHERE first_key like 'bunched-transactions' 
    INTO _count;

    perform pgunit.assertNotNull('event does not exists', _event);
    perform pgunit.assertTrue('number of bunched events should be at least 1', _count > 0);

    DROP TABLE tmp_events;

end;
$BODY$;
ALTER PROCEDURE pgunit.test_case_wash_trade_bunched_existing_fail()
    OWNER TO ebl_staging_o;
