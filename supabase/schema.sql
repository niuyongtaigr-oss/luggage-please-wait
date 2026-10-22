-- ==========================================================================
-- 行李箱请等等 · Supabase Schema
-- 在 Supabase Dashboard → SQL Editor 里整段粘贴执行。
-- 设计要点：
--   1. 三张表 + 一个唯一索引（一个人对一份申请只能投一次）
--   2. RLS 全关，所有读写只能走 security definer 的 RPC
--   3. 身份 = 客户端生成的 device_id（不做登录，见 docs/02 §6.6）
-- ==========================================================================

-- ---------------------------------------------------------------------------
-- 1. 表
-- ---------------------------------------------------------------------------

create table if not exists public.applications (
  id          uuid primary key default gen_random_uuid(),
  device_id   text not null,
  scene       text not null,
  leaving     text not null,
  if_not      text not null,
  avoid       text not null,
  created_at  timestamptz not null default now()
);

create table if not exists public.reasons (
  id             uuid primary key default gen_random_uuid(),
  application_id uuid not null references public.applications(id) on delete cascade,
  device_id      text not null,
  identity       text not null,
  vote           text not null check (vote in ('go','think')),
  body           text not null check (char_length(body) between 2 and 60),
  extra          text,
  helpful        int  not null default 0,
  created_at     timestamptz not null default now(),
  -- ★ 核心约束：一个人对一份申请，只能有一句
  unique (application_id, device_id)
);

create table if not exists public.routes (
  id         uuid primary key default gen_random_uuid(),
  mood       text not null,
  name       text not null,
  dist       text,
  thing      text not null,
  verified   int default 0,
  worth      int default 0,
  source     text,
  created_at timestamptz default now()
);

create index if not exists idx_app_created  on public.applications(created_at desc);
create index if not exists idx_reason_app   on public.reasons(application_id, vote);

-- ---------------------------------------------------------------------------
-- 2. RLS：全关。anon 不能直接碰任何表，只能调下面的 RPC。
--    （不建 policy 就是拒绝，这是 Supabase 的默认行为）
-- ---------------------------------------------------------------------------
alter table public.applications enable row level security;
alter table public.reasons      enable row level security;
alter table public.routes       enable row level security;

-- ---------------------------------------------------------------------------
-- 3. RPC：前端唯一入口
-- ---------------------------------------------------------------------------

-- 3.0 轮次起点：今天 00:00（上海）。所有「今天」都用它，不用 current_date（那是 UTC）
create or replace function public.round_start()
returns timestamptz
language sql stable
as $$
  select (date_trunc('day', now() at time zone 'Asia/Shanghai')
          at time zone 'Asia/Shanghai');
$$;

-- 3.1 启动：只回常量和路线卡，不含任何申请内容
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

-- 3.2 交申请：返回序号
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

-- 3.3 取一份待审的：同场景优先 → 全池兜底，排除自己的、排除审过的
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
    'avoid',   a.avoid,
    -- 这张卡是今天第几份交上来的（前端标题用）
    'no',      (
      select count(*) from applications x
      where x.created_at >= round_start()
        and x.created_at <= a.created_at
    )
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

-- 3.4 交理由：靠唯一索引兜底，重复提交返回 already_reviewed
create or replace function public.api_submit_reason(
  p_device text, p_application uuid, p_identity text,
  p_vote text, p_body text, p_extra text
)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare v_owner text;
begin
  -- 不能审自己
  select device_id into v_owner from applications where id = p_application;
  if v_owner is null then return json_build_object('error','not_found'); end if;
  if v_owner = p_device then return json_build_object('error','self_review'); end if;

  insert into reasons(application_id, device_id, identity, vote, body, extra)
  values (p_application, p_device, p_identity, p_vote, left(p_body,60), nullif(trim(p_extra),''));

  return json_build_object('ok', true);

exception
  when unique_violation then
    return json_build_object('error', 'already_reviewed');
end $$;

-- 3.5 我的判决：最近一份有回应的申请 + 计数 + 三类声音各一句
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

  -- 三类声音各一句：劝走 / 劝留，各取 helpful 最高的一条
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

-- 3.6 交一条小路
create or replace function public.api_submit_route(
  p_where text, p_how text, p_thing text
)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare v_id uuid;
begin
  if coalesce(trim(p_where),'')='' or coalesce(trim(p_how),'')=''
     or coalesce(trim(p_thing),'')='' then
    return json_build_object('error','missing_fields');
  end if;
  insert into routes(mood, name, dist, thing, verified, worth, source)
  values (left(p_where,16), '你交的路', '待了 ' || left(p_how,10),
          left(p_thing,46), 1, 0, '来源：你刚交的 · 未核实')
  returning id into v_id;
  return json_build_object('id', v_id);
end $$;

-- ---------------------------------------------------------------------------
-- 4. 授权：只给 anon 调 RPC 的权限，表权限一律不给
-- ---------------------------------------------------------------------------
revoke all on public.applications, public.reasons, public.routes from anon, authenticated;
grant execute on function public.round_start()                    to anon;
grant execute on function public.api_bootstrap()                 to anon;
grant execute on function public.api_submit_application(text,text,text,text,text) to anon;
grant execute on function public.api_next_application(text,text) to anon;
grant execute on function public.api_submit_reason(text,uuid,text,text,text,text) to anon;
grant execute on function public.api_my_verdict(text)            to anon;
grant execute on function public.api_submit_route(text,text,text) to anon;

-- ---------------------------------------------------------------------------
-- 5. 种子数据：三条路线（申请池留空，现场由评委真填出来才有意思）
-- ---------------------------------------------------------------------------
-- 自愈：如果这份 SQL 之前跑过两次，先把重复路线清掉，每条路由只留一条
-- （不能用 min(id)：Postgres 没有 min(uuid)，会直接报错）
delete from public.routes
where id in (
  select id from (
    select id, row_number() over (partition by name order by created_at, id) as rn
    from public.routes
  ) t where t.rn > 1
);

-- 路线名唯一：防止再插重复
do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'routes_name_key') then
    alter table public.routes add constraint routes_name_key unique (name);
  end if;
end $$;

-- 幂等：靠 name 判重（on conflict 在没有唯一约束时是空操作，这里不用它）
insert into public.routes (mood, name, dist, thing, verified, worth, source)
select v.mood, v.name, v.dist, v.thing, v.verified, v.worth, v.source
from (values
  ('想消失','杨浦滨江线','4.1 km · 3 站','这座桥 1993 年 10 月 23 日通车。今天它过生日。',9,5,'来源：公开史料 · 可查'),
  ('想安静','愚园线','3.2 km · 4 站','这一带真正安静的咖啡馆都在二楼。一楼太吵，三楼太贵。',9,5,'来源：居住经验 · 未核实'),
  ('想热闹','外滩 · 北苏州河线','2.8 km · 4 站','外滩的楼都朝西。下午四点去，光是从江那边打过来的。',14,11,'来源：公开史料 · 可查')
) as v(mood,name,dist,thing,verified,worth,source)
where not exists (select 1 from public.routes r where r.name = v.name);
