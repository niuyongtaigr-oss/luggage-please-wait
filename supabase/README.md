# Supabase 运维手册

> 这份文件回答三个问题：**该跑哪些 SQL、换库改哪里、演示前清什么。**
> 页面本身的运行见根目录 `README.md`。

---

## 0. 三条必读

### ① 这些 SQL 文件分别干什么

| 文件 | 什么时候跑 | 作用 |
|---|---|---|
| **`schema.sql`** | **新项目只跑这一个** | 建 3 张表 + 唯一索引 + 6 个函数 + RLS + 授权 + 3 条种子路线 |
| `patch-002-round.sql` | 老库升级 | 把「一轮」改成上海自然日（`current_date` 是 UTC，会错一天） |
| `patch-003-card-no.sql` | 老库升级 | 审批页「今天第 N 份」返回真实卡号 |
| `patch-004-route-card.sql` | 老库升级 | 小路卡片排版改成「[上海] 待了 10年」，并修正历史数据 |
| `fix-routes.sql` | 一次性 | 清掉历史重复的路线卡，并加唯一约束防止再犯 |

**全部可以重复执行，不会删业务数据。**

- 新开一个项目 → 只跑 `schema.sql`（它已经包含 002/003/004 的全部逻辑）
- 已经在跑的库 → 按 002 → 003 → 004 顺序补

### ② 换 URL / Key 只改一个地方

`config.js`，两个值必须**成对换**：

```js
window.LUG_CONFIG = {
  supabaseUrl: "https://新项目.supabase.co",
  supabaseKey: "sb_publishable_新项目的key"
};
```

改完 `git push`，Pages 约 30–60 秒生效。

### ③ 演示前清一次

```sql
truncate table public.reasons;
truncate table public.applications;
delete from public.routes where source like '来源：你刚交的%';
```

清完应该是：申请 **0 份**、路线 **3 张**。

---

## 一、换到另一个 Supabase 项目

### 必须做的五步

| # | 做什么 | 为什么 |
|---|---|---|
| 1 | 新项目里**整段跑 `schema.sql`** | 表、函数、权限都在那个库里，不会跟着 config 走 |
| 2 | `config.js` 换成新项目的 **URL + anon key** | 两个值来自同一个项目，混用会 401 |
| 3 | `git push` 并等 Pages 重新构建 | 30–60 秒，期间访问到的还是旧配置 |
| 4 | 打开 `?live=1`，确认角标是「在线 · 真实池子」 | 只验证这一点不够，见下面三步自测 |
| 5 | 跑 §二 的「三步自测」 | 确认不是连上了个空壳 |

### 换库后**一定会遇到**的三件事

**① 判决书变成「你的牌还在转盘上」**

浏览器里存着**旧库的 `device_id`**。新库里没有这个 ID 交过的申请，所以查不到判决。

这不是 bug。清掉即可：

```js
localStorage.removeItem('lug_device')
```

或者用无痕窗口打开。

**② 池子空了，审批页抽不到卡片**

新库刚建，一条申请都没有。页面会自动回落到演示数据，并在卡片下面标一行：

> 池子里还没有别人交的申请 —— 这一条是演示数据

这是设计好的降级行为，不是错误。

**③ 路线卡只有 3 张固定的**

种子数据是 `schema.sql` 里插的。旧库里你自己加的那条「小路」不会跟过来。

### 绝对不能做的两件事

**❌ 不要把 `service_role` / `sb_secret_` 开头的 key 放进 `config.js`**

它能绕过所有权限。前端代码是公开的，等于把数据库交给所有人。

`sb_publishable_` / anon key 是**设计上就允许公开**的，放进去没问题，提交到 GitHub 也没问题。

**❌ 不要只换 key 不换 URL**

key 失效返回 `401`，但页面不会崩——它会静默回落到静态轨，角标变「离线」。
**看到「离线」先查 `config.js`，而不是查网络。**

### 换库前后对照

| 项 | 换库前 | 换库后 |
|---|---|---|
| 申请数据 | 旧库里 | **不会跟过来** |
| 路线种子 | 旧库里 | `schema.sql` 跑的 3 张 |
| 自己交的小路 | 旧库里 | 不会跟过来 |
| 函数与权限 | 旧库里 | `schema.sql` 重新建 |
| 设备识别 | 浏览器里的旧 device_id | 需清掉重来 |
| CORS | 无需配置 | 无需配置（Supabase 默认 `*`） |

---

## 二、三步自测（换库后必跑）

```bash
U="https://新项目.supabase.co"
K="sb_publishable_新key"
```

**① 函数在不在**

```bash
curl -s -X POST "$U/rest/v1/rpc/api_bootstrap" \
  -H "apikey: $K" -H "Authorization: Bearer $K" \
  -H "Content-Type: application/json" -d '{}'
```

应返回 `{"poolSize":0,"routes":[…]}` 且 `routes` 3 条。
返回 `PGRST202` 说明 `schema.sql` 没跑完。

**② 表有没有被锁死**

```bash
curl -s "$U/rest/v1/applications?select=*" -H "apikey: $K"
```

应返回 `42501 permission denied`。
**如果返回了数据，说明 RLS 或 `revoke` 没生效——数据是公开的，必须立刻修。**

**③ 唯一索引在不在**

SQL Editor 里跑：

```sql
select indexname from pg_indexes
where tablename = 'reasons' and indexname like '%application_id%device_id%';
```

**返回空就说明「一个人对一份只能投一次」没生效**，重跑 `schema.sql`。

---

## 三、演示前五分钟

### 清数据

```sql
truncate table public.reasons;
truncate table public.applications;
delete from public.routes where source like '来源：你刚交的%';
```

### 确认清干净

```sql
select
  (select count(*) from public.applications) as 申请,
  (select count(*) from public.routes)       as 路线,
  (select count(*) from public.reasons)      as 理由;
```

期望：`0 / 3 / 0`

### 页面确认

打开线上地址加 `?live=1`：

- 顶栏显示「今天刚开始」，不是「今天第 0 份」
- 角标是「在线 · 真实池子」
- 池子说明是「今天还没有人交。你可以是第一个。」

### 来不及清怎么办

**不清也能演示**，只是：

- 序号从 8 开始，不是从 1
- 审批页可能抽到测试数据（「联动测试用」这类句子）
- 评委看到会问

所以**要么清，要么全程用静态轨**（不加 `?live=1`）。静态轨不读数据库，清不清都一样。

---

## 四、日常运维 SQL

### 重置申请与理由

```sql
truncate table public.reasons;
truncate table public.applications;
```

### 只重置路线（恢复三张种子卡）

```sql
delete from public.routes where source like '来源：你刚交的%';
```

### 看今天到底有多少

```sql
select count(*) from public.applications where created_at >= public.round_start();
```

### 看某个设备交了什么

```sql
select * from public.applications where device_id = '这里替换' order by created_at desc;
```

### 修路线重复（历史遗留）

```sql
delete from public.routes
where id in (
  select id from (
    select id, row_number() over (partition by name order by created_at, id) as rn
    from public.routes
  ) t where t.rn > 1
);

alter table public.routes add constraint routes_name_key unique (name);
```

> 别用 `min(id)`：Postgres 没有 uuid 的聚合函数，会直接报错。踩过。

### 整体重建

```sql
drop table if exists public.reasons cascade;
drop table if exists public.applications cascade;
drop table if exists public.routes cascade;
drop function if exists public.round_start();
drop function if exists public.api_bootstrap();
drop function if exists public.api_submit_application(text,text,text,text,text);
drop function if exists public.api_next_application(text,text);
drop function if exists public.api_submit_reason(text,uuid,text,text,text,text);
drop function if exists public.api_my_verdict(text);
drop function if exists public.api_submit_route(text,text,text);
```

然后重新跑 `schema.sql`。

---

## 五、常见问题

| 现象 | 原因 | 处理 |
|---|---|---|
| 角标「离线 · 演示数据」 | config 没填 / key 错 / 网络 | 先查 `config.js`，再看 §二① |
| 控制台 401 | anon key 不对，或 URL 与 key 不同项目 | 成对重填 |
| `PGRST202` 找不到函数 | `schema.sql` 没跑完 | 重跑 |
| `PGRST205` 找不到表 | 同上 | 重跑 |
| `42501 permission denied` | 正常。anon 不该直接读表 | 无需处理 |
| 提交后序号一直是 1 | 时区问题（老版本） | 跑 `patch-002` |
| 审批页只有「等待你的判断」没有数字 | 卡号补丁没跑 | 跑 `patch-003` |
| 小路卡片显示「你交的路」 | 排版补丁没跑 | 跑 `patch-004` |
| 免费项目打不开 | 7 天不活动被暂停 | Dashboard 里点恢复 |

---

## 六、当前使用的项目

| 项 | 值 |
|---|---|
| Project URL | `https://yxsjtjsbawnaonpvyowk.supabase.co` |
| Key 类型 | `sb_publishable_…`（可公开） |
| 建表时间 | 2026-10-22 17:44 |
| 补丁状态 | 002 ✅ 003 ✅ 004 ✅ |

> 换项目时**连这一节一起改**，否则下次没人知道线上连的是哪个库。
