
// harvest-nvd-detail.mjs — 补采：参考链接 / 影响版本 / CVSS 向量 / 在野利用线索
import fs from "node:fs";
import path from "node:path";

const RAW = path.resolve("E:/ds/ARTEXX-iOS/resources/cve/raw2");
fs.mkdirSync(RAW, { recursive: true });
const LOG = path.join(RAW, "detail.log");
const log = (...a) => { const s = "[" + new Date().toISOString().slice(11, 19) + "] " + a.join(" "); console.log(s); fs.appendFileSync(LOG, s + "\n"); };
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

const START = new Date("2023-01-01T00:00:00.000Z");
const END = new Date("2026-11-19T00:00:00.000Z");
const WIN_DAYS = 100, PAGE = 2000, GAP = 6200;
const iso = (d) => d.toISOString().replace(/\.\d{3}Z$/, ".000");

async function api(url, tries = 6) {
  for (let i = 0; i < tries; i++) {
    try {
      const ctl = new AbortController();
      const t = setTimeout(() => ctl.abort(), 120000);
      const r = await fetch(url, { signal: ctl.signal, headers: { "User-Agent": "ARTEXX-iOS/1.0" } });
      clearTimeout(t);
      if (r.status === 200) return await r.json();
      log("HTTP", r.status, "retry", i);
      await sleep(15000 * (i + 1));
    } catch (e) { log("ERR", String(e.message).slice(0, 80)); await sleep(10000 * (i + 1)); }
  }
  return null;
}

function score(metrics) {
  for (const k of ["cvssMetricV40","cvssMetricV31","cvssMetricV30","cvssMetricV2"]) {
    const arr = metrics?.[k];
    if (Array.isArray(arr) && arr.length) {
      const best = arr.map((m) => m.cvssData || {}).sort((a,b)=>(b.baseScore||0)-(a.baseScore||0))[0];
      if (best && typeof best.baseScore === "number") return { s: best.baseScore, v: best.vectorString || "" };
    }
  }
  return null;
}

// 版本范围：从 configurations 的 cpeMatch 提取受影响区间
function ranges(cfg) {
  const out = [];
  for (const c of cfg || []) for (const n of c.nodes || []) {
    const walk = (nd) => {
      for (const m of nd.cpeMatch || []) {
        if (m.vulnerable === false) continue;
        const parts = (m.criteria || "").split(":");
        const product = parts[4] || "", ver = parts[5] || "";
        out.push({
          p: product, v: ver === "*" ? "" : ver,
          vs: m.versionStartIncluding || "", ve: m.versionEndExcluding || "",
          vse: m.versionEndIncluding || "", vss: m.versionStartExcluding || "",
        });
      }
      for (const ch of nd.children || []) walk(ch);
    };
    walk(n);
  }
  return out.slice(0, 6);
}

(async () => {
  let cursor = new Date(START);
  let kept = 0;
  while (cursor < END) {
    const winEnd = new Date(Math.min(cursor.getTime() + WIN_DAYS * 86400000, END.getTime()));
    const tag = cursor.toISOString().slice(0, 10) + "_" + winEnd.toISOString().slice(0, 10);
    const file = path.join(RAW, "d-" + tag + ".json");
    if (!fs.existsSync(file)) {
      const rows = [];
      let startIndex = 0, total = Infinity, pages = 0;
      while (startIndex < total && pages < 60) {
        const url = "https://services.nvd.nist.gov/rest/json/cves/2.0?pubStartDate=" + encodeURIComponent(iso(cursor)) +
          "&pubEndDate=" + encodeURIComponent(iso(winEnd)) + "&resultsPerPage=" + PAGE + "&startIndex=" + startIndex;
        const j = await api(url);
        if (!j) { log("FAIL", tag, startIndex); break; }
        total = j.totalResults; pages++;
        for (const v of j.vulnerabilities || []) {
          if (v.cve.vulnStatus === "Rejected") continue;
          const sc = score(v.cve.metrics);
          if (!sc || sc.s < 4.0) continue;
          const desc = (v.cve.descriptions || []).find((d) => d.lang === "en")?.value || "";
          const cwe = [...new Set((v.cve.weaknesses || []).flatMap((w) => (w.description || []).filter((d) => /^CWE-/.test(d.value)).map((d) => d.value)))];
          const urls = (v.cve.references || []).map((r) => r.url).filter((u) => /^https?:/.test(u)).slice(0, 8);
          const flags = (v.cve.references || []).map((r) => (r.tags || []).join(",")).join(",");
          rows.push({ id: v.cve.id, s: sc.s, v: sc.v, cwe, desc, urls, flags, r: ranges(v.cve.configurations), pub: (v.cve.published || "").slice(0, 10) });
        }
        startIndex += PAGE;
        log("page", tag, startIndex + "/" + total, "kept", rows.length);
        if (startIndex < total) await sleep(GAP);
      }
      fs.writeFileSync(file, JSON.stringify(rows));
      kept += rows.length;
      log("WINDOW DONE", tag, rows.length, "cum", kept);
    } else {
      kept += JSON.parse(fs.readFileSync(file, "utf8")).length;
      log("CACHED", tag, "cum", kept);
    }
    cursor = winEnd;
    await sleep(GAP);
  }
  log("ALL DONE", kept);
})();
