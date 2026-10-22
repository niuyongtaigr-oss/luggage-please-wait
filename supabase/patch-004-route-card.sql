-- ==========================================================================
-- patch-004-route-card.sql · 用户交的小路，卡片排版修正
--
-- 现象：交完小路后卡片显示「[上海] 你交的路 · 待了 10年」
--       「你交的路」是系统标签，却占着线路名的位置，读起来别扭。
--
-- 改成：「[上海] 待了 10年」
--       情绪位 = 你在哪（上海），名字位 = 待了多久，里程位留空。
--
-- 不删数据。整段粘进 SQL Editor 跑。
-- ==========================================================================

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
  values (
    left(p_where,16),                       -- 情绪位：你在哪
    '待了 ' || left(p_how,10),              -- 名字位：待了多久
    null,                                   -- 里程位：留空
    left(p_thing,46),
    1, 0, '来源：你刚交的 · 未核实'
  )
  returning id into v_id;

  return json_build_object('id', v_id);
end $$;

grant execute on function public.api_submit_route(text,text,text) to anon;

-- 修正已经交上来的那几条
update public.routes
set name = dist, dist = null
where name = '你交的路' and dist is not null;

-- 验证
select mood, name, dist, thing from public.routes order by created_at;
