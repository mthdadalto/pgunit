-- complain if script is sourced in psql, rather than via CREATE EXTENSION
\echo Use "CREATE EXTENSION pgunit" to load this file. \quit

create type @extschema@.results as (
  test_name varchar,
  successful boolean,
  failed boolean,
  erroneous boolean,
  error_message varchar,
  duration interval);

--
-- Use select * from run_all() to execute all test cases
--
create or replace function @extschema@.run_all() returns setof @extschema@.results as $$
begin
  return query select * from @extschema@.run_suite(NULL);
end;
$$ language plpgsql set search_path from current;

--
-- Executes all test cases part of a suite and returns the test results.
--
-- Each test case will have a setup procedure run first, then a precondition,
-- then the test itself, followed by a postcondition and a tear down.
--
-- The test case stored procedure name has to match 'test_case_<p_suite>%' patern.
-- It is assumed the setup and precondition procedures are in the same schema as
-- the test stored procedure.
--
-- select * from run_suite('my_test'); will run all tests that will have
-- 'test_case_my_test' prefix.
create or replace function @extschema@.run_suite(p_suite TEXT) returns setof @extschema@.results as $$
declare
  l_proc RECORD;
  l_sid INTEGER;
  l_row @extschema@.results%rowtype;
  l_start_ts timestamp;
  l_cmd text;
  l_condition text;
  l_precondition_cmd text;
  l_postcondition_cmd text;
begin
  l_sid := pg_backend_pid();
  for l_proc in select p.proname, n.nspname
			from pg_catalog.pg_proc p join pg_catalog.pg_namespace n
				on p.pronamespace = n.oid
			where p.proname like 'test/_case/_' || COALESCE(p_suite, '') || '%' escape '/'
			order by p.proname loop
    -- check for setup
    l_condition := @extschema@.get_procname(l_proc.proname, 2, 'test_setup');
    if l_condition is not null then
      l_cmd := 'DO $body$ begin perform ' || quote_ident(l_proc.nspname) || '.' || quote_ident(l_condition)
        || '(); end; $body$';
      perform @extschema@.autonomous(l_cmd);
    end if;
    l_row.test_name := quote_ident(l_proc.proname);
    -- check for precondition
    l_condition := @extschema@.get_procname(l_proc.proname, 2, 'test_precondition');
    if l_condition is not null then
      l_precondition_cmd := 'perform @extschema@.run_condition(''' || quote_ident(l_proc.nspname) || '.' || quote_ident(l_condition)
        || '''); ';
    else
      l_precondition_cmd := '';
    end if;
    -- check for postcondition
    l_condition := @extschema@.get_procname(l_proc.proname, 2, 'test_postcondition');
    if l_condition is not null then
      l_postcondition_cmd := 'perform @extschema@.run_condition(''' || quote_ident(l_proc.nspname) || '.' || quote_ident(l_condition)
        || '''); ';
    else
      l_postcondition_cmd := '';
    end if;
    -- execute the test
    l_start_ts := clock_timestamp();
    begin
      l_cmd := 'DO $body$ begin ' || l_precondition_cmd || 'perform ' || quote_ident(l_proc.nspname) || '.' || quote_ident(l_proc.proname)
        || '(); ' || l_postcondition_cmd || ' end; $body$';
      perform @extschema@.autonomous(l_cmd);
      l_row.successful := true;
      l_row.failed := false;
      l_row.erroneous := false;
      l_row.error_message := 'OK';
    exception
      when triggered_action_exception then
        l_row.successful := false;
        l_row.failed := true;
        l_row.erroneous := false;
        l_row.error_message := SQLERRM;
      when others then
        l_row.successful := false;
        l_row.failed := false;
        l_row.erroneous := true;
        l_row.error_message := SQLERRM;
    end;
    l_row.duration = clock_timestamp() - l_start_ts;
    return next l_row;
    -- check for teardown
    l_condition := @extschema@.get_procname(l_proc.proname, 2, 'test_teardown');
    if l_condition is not null then
      l_cmd := 'DO $body$ begin perform ' || quote_ident(l_proc.nspname) || '.' || quote_ident(l_condition)
        || '(); end; $body$';
      perform @extschema@.autonomous(l_cmd);
    end if;
  end loop;
end;
$$ language plpgsql set search_path from current;

--
-- recreates a _ separated string from parts array
--
create or replace function @extschema@.build_procname(parts text[], p_from integer default 1, p_to integer default null) returns text as $$
declare
  name TEXT := '';
  idx integer;
begin
  if p_to is null then
    p_to := array_length(parts, 1);
  end if;
  name := parts[p_from];
  for idx in (p_from + 1) .. p_to loop
    name := name || '_' || parts[idx];
  end loop;

  return name;
end;
$$ language plpgsql set search_path from current immutable;

--
-- Returns the procedure name matching the pattern below
--   <result_prefix>_<test_case_name>
-- Ex: result_prefix = test_setup and test_case_name = company_finance_invoice then it searches for:
--   test_setup_company_finance_invoice()
--   test_setup_company_finance()
--   test_setup_company()
--
-- It returns the name of the first stored procedure present in the database
--
create or replace function @extschema@.get_procname(test_case_name text, expected_name_count integer, result_prefix text) returns text as $$
declare
  array_name text[];
  array_proc text[];
  idx integer;
  len integer;
  proc_name text;
  is_valid integer;
begin
  array_name := string_to_array(test_case_name, '_');
  len := array_length(array_name, 1);
  for idx in expected_name_count + 1 .. len loop
    array_proc := array_proc || array_name[idx];
  end loop;

  len := array_length(array_proc, 1);
  for idx in reverse len .. 1 loop
    proc_name := result_prefix || '_'
      || @extschema@.build_procname(array_proc, 1, idx);
    select 1 into is_valid from pg_catalog.pg_proc where proname = proc_name;
    if is_valid = 1 then
      return proc_name;
    end if;
  end loop;

  return null;
end;
$$ language plpgsql set search_path from current;

--
-- executes a condition boolean function
--
create or replace function @extschema@.run_condition(proc_name text) returns void as $$
declare
  status boolean;
begin
  execute 'select ' || proc_name || '()' into status;
  if status then
    return;
  end if;
  raise exception 'condition failure: %()', proc_name using errcode = 'triggered_action_exception';
end;
$$ language plpgsql set search_path from current;

--
-- Use: select terminate('db name'); to terminate all locked processes
--
create or replace function @extschema@.terminate(db VARCHAR) returns setof record as $$
  SELECT pg_terminate_backend(pid), query
    FROM pg_stat_activity
    WHERE pid != pg_backend_pid() AND datname = db AND state = 'active';
$$ language sql;

--
-- Use: perform autonomous('UPDATE|INSERT|DELETE|SELECT sp() ...'); to
-- change data in a separate transaction.
--
create or replace function @extschema@.autonomous(p_statement VARCHAR) returns void as $$
declare
  l_error_text character varying;
  l_error_detail character varying;
begin
  execute p_statement;
exception
  when others then
    get stacked diagnostics l_error_text = message_text,
                            l_error_detail = pg_exception_detail;
    rollback;
    raise exception '%: Error on executing: % % %', sqlstate, p_statement, l_error_text, l_error_detail
      using errcode = sqlstate;
end;
$$ language plpgsql set search_path from current;

create or replace function @extschema@.assertTrue(message VARCHAR, condition BOOLEAN) returns void as $$
begin
  if condition then
    null;
  else
    raise exception 'assertTrue failure: %', message using errcode = 'triggered_action_exception';
  end if;
end;
$$ language plpgsql set search_path from current immutable;

create or replace function @extschema@.assertTrue(condition BOOLEAN) returns void as $$
begin
  if condition then
    null;
  else
    raise exception 'assertTrue failure' using errcode = 'triggered_action_exception';
  end if;
end;
$$ language plpgsql set search_path from current immutable;

create or replace function @extschema@.assertNotNull(VARCHAR, ANYELEMENT) returns void as $$
begin
  if $2 IS NULL then
    raise exception 'assertNotNull failure: %', $1 using errcode = 'triggered_action_exception';
  end if;
end;
$$ language plpgsql set search_path from current immutable;

create or replace function @extschema@.assertNull(VARCHAR, ANYELEMENT) returns void as $$
begin
  if $2 IS NOT NULL then
    raise exception 'assertNull failure: %', $1 using errcode = 'triggered_action_exception';
  end if;
end;
$$ language plpgsql set search_path from current immutable;

create or replace function @extschema@.fail(VARCHAR) returns void as $$
begin
  raise exception 'test failure: %', $1 using errcode = 'triggered_action_exception';
end;
$$ language plpgsql set search_path from current immutable;
