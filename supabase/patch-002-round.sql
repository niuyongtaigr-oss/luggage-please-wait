-- ==========================================================================
-- patch-002-round.sql · 把「一轮」的定义统一到自然日（Asia/Shanghai）
-- 在 SQL Editor 里整段跑，跑完不用动前端。
--
-- 修的是三处不一致：
--   1. api_bootstrap 原来算「建库以来总数」，应该只算今天
--   2. api_next_application 原来不过滤日期，能审到前天的申请
--   3. current_date 用的是 UTC，「今天」在 0:00–8:00 会算错一天
--
-- 注意：这不会删除任何数据。数据继续累积，只是「哪一轮」被算清楚了。
-- ==========================================================================

-- ---------------------------------------------------------------------------
-- 轮次起点：今天 00:00（上海）
-- ---------------------------------------------------------------------------
create or replace function public.round_start()
returns timestamptz
language sql
stable
as $$
  select (date_trunc('day', now() at time zone 'Asia/Shanghai')
          at time zone 'Asia/Shanghai');
$$;

-- ---------------------------------------------------------------------------
-- 1. bootstrap：池子只算今天
-- ---------------------------------------------------------------------------
create or replace function public.api_bootstrap()
returns json
language sql
security definer
set search_path = public
as $$
  select json_build_object(
    'poolSize', (select count(*) from applications where created_at >= round_start()),
    'routes',   coalesce((select json_agg(r order by r.created_at) from routes r), '[]'::json)
  );
$$;

-- ---------------------------------------------------------------------------
-- 2. 交申请：序号按今天累加（同上，改用 round_start）
-- ---------------------------------------------------------------------------
create or replace function public.api_submit_application(
  p_device text, p_scene text, p_leaving text, p_if_not text, p_avoid text
)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare v_id uuid; v_no int;
begin
  if coalesce(trim(p_leaving),'') = '' or coalesce(trim(p_if_not),'') = ''
     or coalesce(trim(p_avoid),'') = '' then
    return json_build_object('error', 'missing_fields');
  end if;

  insert into applications(device_id, scene, leaving, if_not, avoid)
  values (p_device, p_scene, left(p_leaving,24), left(p_if_not,40), left(p_avoid,40))
  returning id into v_id;

  select count(*) into v_no
  from applications
  where created_at >= round_start();

  return json_build_object('id', v_id, 'no', v_no);
end $$;

-- ---------------------------------------------------------------------------
-- 3. 取待审：只从今天的池子里抽
--    昨天的申请属于「上一轮」，今天的人不该审到
-- ---------------------------------------------------------------------------
create or replace function public.api_next_application(p_device text, p_scene text)
returns json
language sql
security definer
set search_path = public
as $$
  select json_build_object(
    'id',      a.id,
    'scene',   a.scene,
    'leaving', a.leaving,
    'ifNot',   a.if_not,
    'avoid',   a.avoid
  )
  from applications a
  where a.created_at >= round_start()
    and a.device_id <> p_device
    and not exists (
      select 1 from reasons r
      where r.application_id = a.id and r.device_id = p_device
    )
  order by (a.scene = p_scene) desc, random()
  limit 1;
$$;

-- ---------------------------------------------------------------------------
-- 4. 我的判决：刻意**不**限制日期
--    判决是「上一轮」的结果——昨天交的、今天读完了，就该给今天的你看
-- ---------------------------------------------------------------------------
create or replace function public.api_my_verdict(p_device text)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_app record; v_seen int; v_think int; v_q json;
begin
  select * into v_app
  from applications
  where device_id = p_device
    and exists (select 1 from reasons where application_id = applications.id)
  order by created_at desc
  limit 1;

  if v_app is null then return json_build_object('error','no_verdict'); end if;

  select count(distinct device_id),
         count(distinct device_id) filter (where vote = 'think')
    into v_seen, v_think
  from reasons where application_id = v_app.id;

  select coalesce(json_agg(q), '[]'::json) into v_q
  from (
    (select '劝走' as tone, body as text, identity as by, helpful
       from reasons where application_id = v_app.id and vote='go'
       order by helpful desc, created_at limit 1)
    union all
    (select '劝留', body, identity, helpful
       from reasons where application_id = v_app.id and vote='think'
       order by helpful desc, created_at limit 1)
  ) q;

  return json_build_object(
    'application', json_build_object(
      'leaving', v_app.leaving, 'avoid', v_app.avoid, 'scene', v_app.scene),
    'counts', json_build_object('seen', v_seen, 'think', coalesce(v_think,0)),
    'quotes', v_q
  );
end $$;

grant execute on function public.round_start()              to anon;
grant execute on function public.api_bootstrap()            to anon;
grant execute on function public.api_submit_application(text,text,text,text,text) to anon;
grant execute on function public.api_next_application(text,text) to anon;
grant execute on function public.api_my_verdict(text)       to anon;
