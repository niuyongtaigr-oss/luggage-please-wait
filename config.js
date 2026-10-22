/* ==========================================================================
   config.js —— 已填好（2026-10-22 17:36）
   publishable key 本来就是给前端公开用的，放这里是正常的。
   绝对不要把 sb_secret_ 开头的密钥放进这个文件。

   原始说明：
   在 Supabase Dashboard → Project Settings → API 里找：

     Project URL      → supabaseUrl   形如 https://xxxxxxxx.supabase.co
     anon public key  → supabaseKey   形如 eyJhbGciOi...  （很长那串）

   注意：是 anon public，不是 service_role。
   service_role 能绕过所有权限，绝对不能放进前端。
   ========================================================================== */
window.LUG_CONFIG = {
  supabaseUrl: "https://yxsjtjsbawnaonpvyowk.supabase.co",
  supabaseKey: "sb_publishable_zdIrpnoXzHnk22Z1QBTkWg_xD8SqFZJ"
};
