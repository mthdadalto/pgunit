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
  raise notice 'PGUnit_Info: True is True -> PGUnit works :)';
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
  pgunit.run_suite ('pgunit_integrity');
