/*
 * PGUnit Integrity Test
 */
--@test1 -> true
create function test_case_pgunit_integrity_check_true_is_true ()
  returns void
  as $$
begin
  perform
    pgunit.assertTrue (true);
end;
$$
language plpgsql;

--@test2 -> false
create function test_case_pgunit_integrity_check_false_IsNot_True_not_Errnous ()
  returns void
  as $$
begin
  perform
    pgunit.assertTrue (false);
end;
$$
language plpgsql;

--@test3 -> erroneous
create function test_case_pgunit_integrity_check_erroneous ()
  returns void
  as $$
begin
  perform
    pgunit.assertTrue ('a42');
end;
$$
language plpgsql;

select
  *
from
  pgunit.run_suite ('pgunit_integrity');


/*
 * PGUnit Function overloading
 */
-- @test -> true
create function test_case_pgunit_funover_true_single ()
  returns void
  as $$
begin
  perform
    pgunit.assertTrue (true);
end;
$$
language plpgsql;

--todo
-- @test -> true
create function test_case_pgunit_funover_true_msg ()
  returns void
  as $$
begin
  perform
    pgunit.assertTrue ('Test msg', true);
end;
$$
language plpgsql;

--@test2 -> false
create function test_case_pgunit_integrity_check_false_IsNot_True_not_Errnous ()
  returns void
  as $$
begin
  raise notice 'PGUnit_Info: Should fail not erroneous';
  perform
    pgunit.assertTrue (false);
end;
$$
language plpgsql;

--@test3 -> erroneous
create function test_case_pgunit_integrity_check_erroneous ()
  returns void
  as $$
begin
  raise notice 'PGUnit_Info: Should fail erroneous';
  perform
    pgunit.assertTrue ('a42');
end;
$$
language plpgsql;

select
  *
from
  pgunit.run_suite ('pgunit_funover');

create or replace function test_setup_client() returns boolean as $$
declare
id int;
begin
select null into id;
return id is null;
end;
$$ language plpgsql;

create or replace function test_precondition_client() returns boolean as $$
declare
ahvnr_t varchar;
ahv_begin_t varchar;
begin
select '756.1111.1111.11' into ahvnr_t from client where id_client = 1001;
select substr(ahvnr_t, 0, 4) into ahv_begin_t;
return ahvnr_t is not null and (ahv_begin_t = '756');
end;
$$ language plpgsql;

create or replace function test_case_client_1() returns void as $$
begin
  perform
    pgunit.assertFalse (false);
end;
$$
language plpgsql;

create or replace function test_postcondition_client() returns boolean as $$
declare
id int;
begin
select 2 into id;
return id is not null and (id = 2);
end;
$$ language plpgsql;

create or replace function test_teardown_client() returns boolean as $$
declare
id int;
begin
select 2 into id;
return id is not null and (id = 2);
end;
$$ language plpgsql;

select
  *
from
  pgunit.run_suite ('client');
/*
