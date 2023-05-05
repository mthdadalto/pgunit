-- Version 0.1.2
--CREATE EXTENSION pgunit;

create type pgunit.results as (
  test_name varchar,
  successful boolean,
  failed boolean,
  erroneous boolean,
  error_message varchar,
  duration interval
);

--
-- Use select * from run_all() to execute all test cases
--
create or replace function pgunit.run_all ()
  returns setof pgunit.results
  as $$
begin
  return query
  select
    *
  from
    pgunit.run_suite (null);
end;
$$
language plpgsql
set search_path
from
  current;

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
create or replace function pgunit.run_suite (p_suite text)
  returns setof pgunit.results
  as $$
declare
  l_proc RECORD;
  l_sid integer;
  l_row pgunit.results%rowtype;
  l_start_ts timestamp;
  l_cmd text;
  l_condition text;
  l_precondition_cmd text;
  l_postcondition_cmd text;
begin
  l_sid := pg_backend_pid();
  for l_proc in
  select
    p.proname,
    n.nspname
  from
    pg_catalog.pg_proc p
    join pg_catalog.pg_namespace n on p.pronamespace = n.oid
  where
    p.proname like 'test/_case/_' || COALESCE(p_suite, '') || '%' escape '/'
  order by
    p.proname loop
      -- check for setup
      l_condition := pgunit.get_procname (l_proc.proname, 2, 'test_setup');
      if l_condition is not null then
        l_cmd := 'DO $body$ begin CALL ' || quote_ident(l_proc.nspname) || '.' || quote_ident(l_condition) || '(); end; $body$';
        perform
          pgunit.autonomous (l_cmd);
      end if;
      l_row.test_name := quote_ident(l_proc.proname);
      -- check for precondition
      l_condition := pgunit.get_procname (l_proc.proname, 2, 'test_precondition');
      if l_condition is not null then
        l_precondition_cmd := 'CALL pgunit.run_condition(''' || quote_ident(l_proc.nspname) || '.' || quote_ident(l_condition) || '''); ';
      else
        l_precondition_cmd := '';
      end if;
      -- check for postcondition
      l_condition := pgunit.get_procname (l_proc.proname, 2, 'test_postcondition');
      if l_condition is not null then
        l_postcondition_cmd := 'CALL pgunit.run_condition(''' || quote_ident(l_proc.nspname) || '.' || quote_ident(l_condition) || '''); ';
      else
        l_postcondition_cmd := '';
      end if;
      -- execute the test
      l_start_ts := clock_timestamp();
      begin
        l_cmd := 'DO $body$ begin ' || l_precondition_cmd || 'CALL ' || quote_ident(l_proc.nspname) || '.' || quote_ident(l_proc.proname) || '(); ' || l_postcondition_cmd || ' end; $body$';
        perform
          pgunit.autonomous (l_cmd);
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
  l_condition := pgunit.get_procname (l_proc.proname, 2, 'test_teardown');
  if l_condition is not null then
    l_cmd := 'DO $body$ begin CALL ' || quote_ident(l_proc.nspname) || '.' || quote_ident(l_condition) || '(); end; $body$';
    perform
      pgunit.autonomous (l_cmd);
    end if;
  end loop;
end;

$$
language plpgsql
set search_path
from
  current;

--
-- recreates a _ separated string from parts array
--
create or replace function pgunit.build_procname (parts text[], p_from integer default 1, p_to integer default null)
  returns text
  as $$
declare
  name text := '';
  idx integer;
begin
  if p_to is null then
    p_to := array_length(parts, 1);
  end if;
  name := parts[p_from];
  for idx in (p_from + 1)..p_to loop
    name := name || '_' || parts[idx];
  end loop;
  return name;
end;
$$
language plpgsql
set search_path
from
  current immutable;

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
create or replace function pgunit.get_procname (test_case_name text, expected_name_count integer, result_prefix text)
  returns text
  as $$
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
  for idx in expected_name_count + 1..len loop
    array_proc := array_proc || array_name[idx];
  end loop;
  len := array_length(array_proc, 1);
  for idx in reverse len..1 loop
    proc_name := result_prefix || '_' || pgunit.build_procname (array_proc, 1, idx);
    select
      1 into is_valid
    from
      pg_catalog.pg_proc
    where
      proname = proc_name;
    if is_valid = 1 then
      return proc_name;
    end if;
  end loop;
  return null;
end;
$$
language plpgsql
set search_path
from
  current;

--
-- executes a condition boolean function
--
create or replace function pgunit.run_condition (proc_name text)
  returns void
  as $$
declare
  status boolean;
begin
  execute 'select ' || proc_name || '()' into status;
  if status then
    return;
  end if;
  raise exception 'condition failure: %()', proc_name
    using errcode = 'triggered_action_exception';
end;
$$
language plpgsql
set search_path
from
  current;

--
-- Use: select terminate('db name'); to terminate all locked processes
--
create or replace function pgunit.terminate (db varchar)
  returns setof record
  as $$
  select
    pg_terminate_backend(pid),
    query
  from
    pg_stat_activity
  where
    pid != pg_backend_pid()
    and datname = db
    and state = 'active';

$$
language sql;

--
-- Use: perform autonomous('UPDATE|INSERT|DELETE|SELECT sp() ...'); to
-- change data in a separate transaction.
--
create or replace function pgunit.autonomous (p_statement varchar)
  returns void
  as $$
declare
  l_error_text character varying;
  l_error_detail character varying;
begin
  set search_path to default;
  execute p_statement;
  set search_path from current; -- TODO ugly
exception
  when triggered_action_exception then
  -- this is triggered when condition is false but should be true and vice versa
    set search_path from current; -- TODO ugly
    get stacked diagnostics l_error_text = message_text;
    raise exception '%',l_error_text using errcode = 'triggered_action_exception';
  when others then
    set search_path from current; -- TODO ugly
    get stacked diagnostics l_error_text = message_text, l_error_detail = pg_exception_detail;
    raise exception '%',l_error_text using errcode = 'syntax_error';
rollback;
  -- never actually reached
  raise exception '%: Error on executing: % % %', sqlstate, p_statement, l_error_text, l_error_detail using errcode = sqlstate;
end;

$$
language plpgsql
set search_path
from
  current;

create or replace function pgunit.assertTrue (message varchar, condition boolean)
  returns void
  as $$
begin
  if condition then
    null;
  else
    raise exception 'assertTrue failure: %', message
      using errcode = 'triggered_action_exception';
    end if;
end;
$$
language plpgsql
set search_path
from
  current immutable;

create or replace function pgunit.assertTrue (condition boolean)
  returns void
  as $$
begin
  if condition then
    null;
  else
    raise exception 'assertTrue failure'
      using errcode = 'triggered_action_exception';
    end if;
end;
$$
language plpgsql
set search_path
from
  current immutable;

create or replace function pgunit.assertFalse (message varchar, condition boolean)
  returns void
  as $$
begin
  if not condition then
    null;
  else
    raise exception 'assertFalse failure: %', message
      using errcode = 'triggered_action_exception';
    end if;
end;
$$
language plpgsql
set search_path
from
  current immutable;

create or replace function pgunit.assertFalse (condition boolean)
  returns void
  as $$
begin
  if not condition then
    null;
  else
    raise exception 'assertFalse failure'
      using errcode = 'triggered_action_exception';
    end if;
end;
$$
language plpgsql
set search_path
from
  current immutable;

create or replace function pgunit.assertNotNull (message varchar, ANYELEMENT)
  returns void
  as $$
begin
  if $2 is null then
    raise exception 'assertNotNull failure: %', message
      using errcode = 'triggered_action_exception';
    end if;
end;
$$
language plpgsql
set search_path
from
  current immutable;

create or replace function pgunit.assertNotNull (ANYELEMENT)
  returns void
  as $$
begin
  if $2 is null then
    raise exception 'assertNotNull failure'
      using errcode = 'triggered_action_exception';
    end if;
end;
$$
language plpgsql
set search_path
from
  current immutable;

create or replace function pgunit.assertNull (varchar, ANYELEMENT)
  returns void
  as $$
begin
  if $2 is not null then
    raise exception 'assertNull failure: %', $1
      using errcode = 'triggered_action_exception';
    end if;
end;
$$
language plpgsql
set search_path
from
  current immutable;

create or replace function pgunit.assertNull (ANYELEMENT)
  returns void
  as $$
begin
  if $1 is not null then
    raise exception 'assertNull failure'
      using errcode = 'triggered_action_exception';
    end if;
end;
$$
language plpgsql
set search_path
from
  current immutable;

create or replace function pgunit.assertFound (ANYELEMENT)
  returns void
  as $$
begin
  if $1 is not null then
    raise exception 'assertNull failure'
      using errcode = 'triggered_action_exception';
    end if;
end;
$$
language plpgsql
set search_path
from
  current immutable;

create or replace function pgunit.fail (varchar)
  returns void
  as $$
begin
  raise exception 'test failure: %', $1
    using errcode = 'triggered_action_exception';
end;
$$
language plpgsql
set search_path
from
  current immutable;
