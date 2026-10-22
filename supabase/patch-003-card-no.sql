-- ==========================================================================
-- patch-003-card-no.sql · 让「今天第 N 份」有真实来源
--
-- 问题：审批页大标题原来读 data.js 里写死的 reviewNo=12，
--       在线模式下池子只有 8 份，却显示「今天第 12 份」。
--       服务端本来就没有「待审队列第几号」这个概念，那个 12 是编的。
--
-- 修法：让 api_next_application 返回这张卡自己的序号
--       —— 它是今天第几份被交上来的申请。
--
-- 不删任何数据，只替换一个函数。整段粘进 SQL Editor 跑。
-- ==========================================================================

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
    -- 这张卡是今天第几份交上来的
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

grant execute on function public.api_next_application(text,text) to anon;

-- 验证：连抽 3 次，每次应带 no 字段，且 no ≤ 今天的总份数
select
  (select count(*) from public.applications where created_at >= public.round_start()) as 今日份数,
  (public.api_next_application('probe-verify','租房') ->> 'no')                    as 抽到的卡是第几份;
