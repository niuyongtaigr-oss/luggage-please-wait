# Supabase 接入 · 5 分钟做完

目标：让 `?live=1` 连上真实数据库——池子是真池子，41 是真去重后的人数。

**做完之前，静态演示完全不受影响**（没填密钥就自动走 `data.js`）。

---

## 一、建项目（约 2 分钟）

1. 打开 <https://supabase.com> → 用 GitHub 账号登录（免绑卡）
2. **New project**
   - Name：`luggage`
   - Database Password：随便设一个，**记下来**（后面基本用不到）
   - Region：**Southeast Asia (Singapore)** ← 离上海最近
   - Plan：Free
3. 等约 60 秒，项目初始化完成

---

## 二、建表（约 1 分钟）

1. 左侧菜单 → **SQL Editor** → **New query**
2. 打开本仓库的 `supabase/schema.sql`，**整段复制粘贴**进去
3. 点 **Run**（或 `Ctrl/⌘ + Enter`）
4. 看到 `Success. No rows returned` 就成了

> 这个 SQL 会建三张表、一个唯一索引、六个 RPC 函数，并塞进三条路线卡。
> 重复执行不会报错（全是 `if not exists` / `on conflict do nothing`）。

---

## 三、拿两个值（约 1 分钟）

左侧菜单最下方 → **Project Settings** → **API**

| 界面上叫什么 | 对应 | 长什么样 |
|---|---|---|
| **Project URL** | `supabaseUrl` | `https://abcdefghijkl.supabase.co` |
| **anon / public** | `supabaseKey` | `eyJhbGciOiJIUzI1NiIs...`（很长一串） |

> ⚠️ 是 **anon public**，不是 `service_role`。
> `service_role` 能绕过所有权限，**绝对不能放进前端**。

---

## 四、填进 config.js

打开仓库根目录的 `config.js`：

```js
window.LUG_CONFIG = {
  supabaseUrl: "https://abcdefghijkl.supabase.co",
  supabaseKey: "eyJhbGciOiJIUzI1NiIs..."
};
```

保存。完事。

---

## 五、验证

> ✅ 本项目已在 `yxsjtjsbawnaonpvyowk` 上实测通过（2026-10-22 17:52）：
> 序号真实累加、不会抽到自己、重复提交被唯一索引拦、自我审批被拒、判决按 `distinct device_id` 聚合。


```bash
# 打开在线模式
index.html?live=1
```

顶栏右侧会出现一个角标：

| 角标 | 含义 |
|---|---|
| ● **在线 · 真实池子** | 连接成功，池子是真的 |
| ● **离线 · 演示数据** | 连不上，已自动回落，演示照常 |
| （不显示） | 没加 `?live=1`，走静态轨 |

**自测三步：**

1. `Ctrl+K` 填表 → 提交 → 幕布上的数字应该是**真实序号**（第一次是 1，不是 47）
2. 审批页应该抽到**别人交的那份**（你自己交的那份不会出现）
3. 再提交一次 → 应该提示「你已经审过这一份了」（唯一索引生效）

---

## 六、它到底怎么保证「不是同一个人」

| 机制 | 在哪 | 作用 |
|---|---|---|
| `device_id` | 浏览器 `localStorage` 生成一次 | 认设备，不认人 |
| `unique (application_id, device_id)` | 数据库索引 | 一个人对一份只能投一次 |
| `a.device_id <> p_device` | `api_next_application` | 不会抽到自己的 |
| `count(distinct device_id)` | `api_my_verdict` | 「41 个人」是去重后的人数 |

**没有登录、没有手机号、没有实名。** 清掉浏览器存储就变成「新的人」——这是刻意的，理由见 `docs/02-技术方案.md` §6.6。

---

## 七、常见问题

| 现象 | 原因 | 处理 |
|---|---|---|
| 角标一直是「离线」 | config 没填 / URL 多了斜杠 / key 用了 service_role | 检查 `config.js` |
| 控制台 `401` | anon key 不对 | 重新复制 anon public |
| 控制台 `404 ... /rpc/api_xxx` | SQL 没跑完 | 重跑一遍 `schema.sql` |
| 控制台 `permission denied` | 表权限被拒（正常） | 前端只该调 RPC，不该直接读表 |
| 提交后序号一直是 1 | 时区问题：`current_date` 用的是 UTC | 演示无所谓；要精确就改成 `now() at time zone 'Asia/Shanghai'` |

---

## 八、临时开关

想中途切回静态轨，把 URL 里的 `?live=1` 删掉即可，**不用改任何代码**。

想彻底关掉在线模式，把 `config.js` 里的两个值清空。

---

## 九、清库（演示前重置）

在 SQL Editor 里跑：

```sql
truncate table public.reasons;
truncate table public.applications;
```

路线卡不动。想恢复三条种子路线，重跑 `schema.sql` 最后那段 `insert`。

---

## 十、运维 SQL（随时可用）

下面三段直接粘进 **SQL Editor** 跑，不需要改任何代码。

### 10.1 演示前重置（最常用）

清空所有申请和理由，让评委现场填出来的才是真的。路线卡不动。

```sql
truncate table public.reasons;
truncate table public.applications;
```

跑完点开页面刷新一下，顶栏应该变成「今天第 0 份」，在线角标不变。

> 为什么要清：池子里如果留着测试数据，评委扫码进来会审到你写的测试句，
> 一眼就看出这是假数据。**清干净，让它从 0 开始长。**

### 10.2 修路线卡重复（我之前留下的坑）

如果你把 `schema.sql` 跑过两次，`routes` 会有 6 条（每张卡两条）。

原因：种子里用了 `on conflict do nothing`，但当时 `routes` 表**没有唯一约束**，
这句话是空操作，插几次就重复几次。

**修法（二选一）：**

**A. 重跑一遍 `schema.sql`** —— 最新的版本自带自愈：会先清重复、再加唯一约束。

**B. 只跑下面这段：**

```sql
-- 去重，每个名字只留一条
delete from public.routes
where id in (
  select id from (
    select id, row_number() over (partition by name order by created_at, id) as rn
    from public.routes
  ) t where t.rn > 1
);

-- 加唯一约束，防止以后再重复
alter table public.routes add constraint routes_name_key unique (name);
```

### 10.3 体检（30 秒确认库是好的）

```sql
-- 应该有 3 条，且没有重复
select name, count(*) from public.routes group by name order by 1;

-- 应该有 6 个函数
select proname from pg_proc where proname like 'api_%' order by 1;

-- 唯一索引在不在（应该有 1 行）
select indexname from pg_indexes
where tablename = 'reasons' and indexname like '%application_id%device_id%';
```

第三条如果查不到，说明 `unique (application_id, device_id)` 没建上，
「一个人对一份只能投一次」就失效了 —— 重跑 `schema.sql`。

### 10.4 整体重建（改坏了，想从头来）

```sql
drop table if exists public.reasons cascade;
drop table if exists public.applications cascade;
drop table if exists public.routes cascade;
drop function if exists public.api_bootstrap();
drop function if exists public.api_submit_application(text,text,text,text,text);
drop function if exists public.api_next_application(text,text);
drop function if exists public.api_submit_reason(text,uuid,text,text,text,text);
drop function if exists public.api_my_verdict(text);
drop function if exists public.api_submit_route(text,text,text);
```

然后重新粘一遍 `schema.sql`。

---

## 十一、上线后核对清单

- [ ] `schema.sql` 跑过，三条体检 SQL 都对
- [ ] `routes` 是 3 条，没有重复
- [ ] 页面加 `?live=1`，角标显示「在线 · 真实池子」
- [ ] 顶栏「今天第 N 份」和实际池子数一致
- [ ] 提交一次，序号 +1
- [ ] 再提交一次，审批页不会抽到自己
- [ ] 同一份投两次，提示「你已经审过这一份了」
- [ ] 断网后刷新，角标变「离线 · 演示数据」，演示照常
- [ ] 演示前跑过 `10.1` 重置

---

## 十二、「数据是累积的」——这件事到底怎么算

数据**永远不删，一直累积**。但页面上的数字不是累计值，是**这一轮**的值。

### 一轮 = 一个自然日（上海时间）

```
poolSize      = 今天 00:00 之后提交的份数
「今天第 N 份」= 今天第几个交的
审批页抽到     = 只从今天的池子里抽
判决书         = 这个 device 最近一份「有人回应过」的申请（可以是昨天的）
```

所以：

| 场景 | 结果 |
|---|---|
| 今天第 1 个交 | 显示「今天第 1 份」 |
| 昨天交了 200 份，今天第 1 个交 | 还是显示「今天第 1 份」 |
| 今天审别人 | 只抽得到今天交的，抽不到昨天的 |
| 昨天交的、今天才被读完 | 你今天打开判决书能看到——这就是「上一轮」 |

**「上一轮」不是文案修辞，是数据结构**：判决不按日期过滤，因为它本来就该跨轮次回来找你。

### 为什么必须用 `round_start()` 而不是 `current_date`

`current_date` 用的是数据库会话时区，Supabase 默认是 **UTC**。
上海时间 0:00–8:00 这段时间，UTC 还是昨天——**凌晨 1 点交的申请会被算进前一天**。

所以全部换成了：

```sql
select date_trunc('day', now() at time zone 'Asia/Shanghai') at time zone 'Asia/Shanghai';
```

### 所以 truncate 不是必须的

`10.1 演示前重置` 是**可选的**，只是为了让序号从小的数字开始、别让评委审到测试句。

不清也不会错：昨天那 4 条测试数据今天就自动不在池子里了，因为它们是「上一轮」。
