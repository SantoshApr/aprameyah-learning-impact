-- =========================================================
-- Aprameyah Learning Impact Platform V4
-- Run AFTER the existing V3 schema.
-- =========================================================

-- Authenticated users can manage admin data.
-- Participant access is handled through narrow SECURITY DEFINER functions.

drop policy if exists "authenticated clients all" on public.clients;
create policy "authenticated clients all"
on public.clients for all to authenticated
using (true) with check (true);

drop policy if exists "authenticated programs all" on public.programs;
create policy "authenticated programs all"
on public.programs for all to authenticated
using (true) with check (true);

drop policy if exists "authenticated modules all" on public.modules;
create policy "authenticated modules all"
on public.modules for all to authenticated
using (true) with check (true);

drop policy if exists "authenticated participants all" on public.participants;
create policy "authenticated participants all"
on public.participants for all to authenticated
using (true) with check (true);

drop policy if exists "authenticated questions all" on public.questions;
create policy "authenticated questions all"
on public.questions for all to authenticated
using (true) with check (true);

drop policy if exists "authenticated assessments all" on public.assessments;
create policy "authenticated assessments all"
on public.assessments for all to authenticated
using (true) with check (true);

drop policy if exists "authenticated responses all" on public.assessment_responses;
create policy "authenticated responses all"
on public.assessment_responses for all to authenticated
using (true) with check (true);

drop policy if exists "authenticated results all" on public.assessment_results;
create policy "authenticated results all"
on public.assessment_results for all to authenticated
using (true) with check (true);

-- Participant package lookup.
create or replace function public.get_assessment_package(p_token text, p_stage text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  p record;
  prog record;
  qs jsonb;
begin
  if p_stage not in ('pre','post') then
    raise exception 'Invalid assessment stage';
  end if;

  select *
  into p
  from public.participants
  where access_token = p_token
  limit 1;

  if not found then
    raise exception 'Invalid assessment link';
  end if;

  select *
  into prog
  from public.programs
  where id = p.program_id;

  select coalesce(jsonb_agg(
    jsonb_build_object(
      'id', q.id,
      'module_id', q.module_id,
      'question_text', q.question_text,
      'skill', q.skill,
      'difficulty', q.difficulty,
      'question_type', q.question_type,
      'options', q.options
    ) order by q.created_at
  ), '[]'::jsonb)
  into qs
  from public.questions q
  where q.program_id = p.program_id
    and q.active = true;

  return jsonb_build_object(
    'participant', jsonb_build_object(
      'id', p.id,
      'name', p.name,
      'email', p.email,
      'employee_id', p.employee_id
    ),
    'program', jsonb_build_object(
      'id', prog.id,
      'name', prog.name,
      'batch_name', prog.batch_name,
      'duration_hours', prog.duration_hours
    ),
    'stage', p_stage,
    'questions', qs
  );
end;
$$;

-- Participant submission. Correct answers are evaluated server-side.
create or replace function public.submit_assessment(
  p_token text,
  p_stage text,
  p_answers jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  p record;
  q record;
  a_id uuid;
  total integer := 0;
  correct integer := 0;
  selected integer;
  module_map jsonb := '{}'::jsonb;
  score numeric(5,2);
begin
  if p_stage not in ('pre','post') then
    raise exception 'Invalid assessment stage';
  end if;

  select * into p
  from public.participants
  where access_token = p_token
  limit 1;

  if not found then
    raise exception 'Invalid assessment link';
  end if;

  if exists (
    select 1 from public.assessments
    where participant_id=p.id and stage=p_stage and status='completed'
  ) then
    raise exception 'This assessment has already been completed';
  end if;

  insert into public.assessments
    (program_id, participant_id, stage, started_at, status)
  values
    (p.program_id, p.id, p_stage, now(), 'started')
  returning id into a_id;

  for q in
    select id, module_id, correct_option
    from public.questions
    where program_id=p.program_id and active=true
  loop
    total := total + 1;
    selected := null;

    begin
      selected := (p_answers ->> q.id::text)::integer;
    exception when others then
      selected := null;
    end;

    if selected is not null and selected = q.correct_option then
      correct := correct + 1;
      module_map := jsonb_set(
        module_map,
        array[coalesce(q.module_id::text,'general'), 'correct'],
        to_jsonb(coalesce((module_map -> coalesce(q.module_id::text,'general') ->> 'correct')::integer,0)+1),
        true
      );
    end if;

    module_map := jsonb_set(
      module_map,
      array[coalesce(q.module_id::text,'general'), 'total'],
      to_jsonb(coalesce((module_map -> coalesce(q.module_id::text,'general') ->> 'total')::integer,0)+1),
      true
    );

    insert into public.assessment_responses
      (assessment_id, question_id, selected_option, is_correct)
    values
      (a_id, q.id, selected, selected is not null and selected=q.correct_option);
  end loop;

  score := case when total=0 then 0 else round((correct::numeric/total::numeric)*100,2) end;

  update public.assessments
  set score=score, correct_answers=correct, total_questions=total,
      completed_at=now(), status='completed'
  where id=a_id;

  insert into public.assessment_results
    (assessment_id, participant_id, overall_score, proficiency_level, module_scores, recommendation)
  values
    (a_id, p.id, score,
     case when score>=85 then 'Advanced'
          when score>=70 then 'Proficient'
          when score>=50 then 'Developing'
          else 'Needs Improvement' end,
     module_map,
     case when score>=85 then 'Move to advanced application/project learning.'
          when score>=70 then 'Reinforce weaker modules through practice or project work.'
          else 'Run a targeted refresher and reassess key objectives.' end);

  return jsonb_build_object(
    'assessment_id', a_id,
    'score', score,
    'correct', correct,
    'total', total
  );
end;
$$;

revoke all on function public.get_assessment_package(text,text) from public;
grant execute on function public.get_assessment_package(text,text) to anon, authenticated;

revoke all on function public.submit_assessment(text,text,jsonb) from public;
grant execute on function public.submit_assessment(text,text,jsonb) to anon, authenticated;
