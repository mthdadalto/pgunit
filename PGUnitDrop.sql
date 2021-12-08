--
-- Clears the PG Unit functions
--
--
drop function run_suite(TEXT);
drop function run_all();
drop function run_condition(proc_name text);
drop function build_procname(parts text[], p_from integer, p_to integer);
drop function get_procname(test_case_name text, expected_name_count integer, result_prefix text);
drop function terminate(db VARCHAR);
drop function autonomous(p_statement VARCHAR);
drop function dblink_connect(text, text);
drop function dblink_disconnect(text);
drop function dblink_exec(text, text);
drop function detect_dblink_schema();
drop function assertTrue(message VARCHAR, condition BOOLEAN);
drop function assertTrue(condition BOOLEAN);
drop function assertNotNull(VARCHAR, ANYELEMENT);
drop function assertNull(VARCHAR, ANYELEMENT);
drop function fail(VARCHAR);
drop type results cascade;
