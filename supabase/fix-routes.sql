-- ==========================================================================
-- fix-routes.sql · 清掉重复的路线卡
-- 症状：换一条页连续两次翻到同一张卡；api_bootstrap 返回 6 条
-- 原因：种子数据用了 on conflict do nothing，但没有唯一约束时它是空操作
--
-- 注意：早先那版用了 min(id)，Postgres 没有 min(uuid)，会直接报错。
-- 这里是正确版本。整段粘进 SQL Editor 跑。
-- ==========================================================================

-- 1. 去重：每个路线名只留最早的一条
delete from public.routes
where id in (
  select id from (
    select id, row_number() over (partition by name order by created_at, id) as rn
    from public.routes
  ) t where t.rn > 1
);

-- 2. 加唯一约束（已存在就跳过）
do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'routes_name_key') then
    alter table public.routes add constraint routes_name_key unique (name);
  end if;
end $$;

-- 3. 验证：应该 3 行，每行 count = 1
select name, count(*) as n from public.routes group by name order by 1;
