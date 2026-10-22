/* ==========================================================================
   api.js —— Supabase 适配层
   设计原则：这一层挂了，主演示不能挂。
   · 只用 fetch，不引 supabase-js（少一个 CDN 失败面）
   · 所有调用 1.5 秒超时，超时即降级
   · 任何异常都往上抛，由 index.html 决定回落到 data.js
   ========================================================================== */
(function(){
  "use strict";

  const CFG = window.LUG_CONFIG || {};
  const URL_BASE = (CFG.supabaseUrl || "").replace(/\/+$/,"");
  const KEY = CFG.supabaseKey || "";

  /* 设备 ID：不是账号，是「这台机器这一轮」的伪匿名 ID。
     清掉 localStorage 就变成新人——这是刻意的，见 docs/02 §6.6 */
  const DEV_KEY = "lug_device";
  function deviceId(){
    let id = null;
    try { id = localStorage.getItem(DEV_KEY); } catch(e){}
    if(!id){
      id = (crypto.randomUUID ? crypto.randomUUID()
            : "dev-" + Date.now().toString(36) + "-" + Math.random().toString(36).slice(2,10));
      try { localStorage.setItem(DEV_KEY, id); } catch(e){}
    }
    return id;
  }

  function rpc(fn, args, ms){
    if(!URL_BASE || !KEY) return Promise.reject(new Error("config_empty"));
    const ctrl = new AbortController();
    const timer = setTimeout(() => ctrl.abort(), ms || 1500);
    return fetch(URL_BASE + "/rest/v1/rpc/" + fn, {
      method: "POST",
      headers: {
        "apikey": KEY,
        "Authorization": "Bearer " + KEY,
        "Content-Type": "application/json"
      },
      body: JSON.stringify(args || {}),
      signal: ctrl.signal
    })
    .then(r => {
      clearTimeout(timer);
      if(!r.ok) return r.text().then(t => { throw new Error(fn + " " + r.status + " " + t.slice(0,120)); });
      return r.json();
    })
    .catch(err => { clearTimeout(timer); throw err; });
  }

  window.LUG_API = {
    /* 配置是否齐了。没配就永远走静态轨。 */
    available(){
      return !!(URL_BASE && KEY);
    },

    deviceId,

    bootstrap(){
      return rpc("api_bootstrap", {});
    },

    submitApplication(d){
      return rpc("api_submit_application", {
        p_device: deviceId(),
        p_scene: d.scene,
        p_leaving: d.leaving,
        p_if_not: d.ifNot,
        p_avoid: d.avoid
      });
    },

    nextApplication(scene){
      return rpc("api_next_application", { p_device: deviceId(), p_scene: scene || "" });
    },

    submitReason(d){
      return rpc("api_submit_reason", {
        p_device: deviceId(),
        p_application: d.applicationId,
        p_identity: d.identity,
        p_vote: d.vote,
        p_body: d.body,
        p_extra: d.extra || ""
      });
    },

    myVerdict(){
      return rpc("api_my_verdict", { p_device: deviceId() });
    },

    submitRoute(d){
      return rpc("api_submit_route", { p_where: d.where, p_how: d.how, p_thing: d.thing });
    }
  };
})();
