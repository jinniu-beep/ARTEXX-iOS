
// harvest-nvd-range.mjs — 按 100 天窗口分页拉取 NVD 全量 CVE，本地过滤 CVSS >= 4.0
import fs from "node:fs";
import path from "node:path";

const ROOT = path.resolve("E:/ds/ARTEXX-iOS/resources/cve");
const RAW = path.join(ROOT, "raw");
fs.mkdirSync(RAW, { recursive: true });
const LOG = path.join(RAW, "nvd.log");
const log = (...a) => { const s = "[" + new Date().toISOString().slice(11, 19) + "] " + a.join(" "); console.log(s); fs.appendFileSync(LOG, s + "\n"); };
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

const START = new Date("2023-01-01T00:00:00.000Z");
const END = new Date("2026-11-19T00:00:00.000Z");
const WIN_DAYS = 100;
const PAGE = 2000;
const GAP = 6200; // 无 API key 限速 5 次/30 秒

function iso(d) { return d.toISOString().replace(/\.\d{3}Z$/, ".000"); }

async function api(url, tries = 6) {
  for (let i = 0; i < tries; i++) {
    try {
      const ctl = new AbortController();
      const t = setTimeout(() => ctl.abort(), 120000);
      const r = await fetch(url, { signal: ctl.signal, headers: { "User-Agent": "ARTEXX-iOS/1.0" } });
      clearTimeout(t);
      if (r.status === 200) return await r.json();
      log("HTTP", r.status, "retry", i, url.slice(60, 140));
      await sleep(15000 * (i + 1));
    } catch (e) { log("ERR", String(e.message).slice(0, 80)); await sleep(10000 * (i + 1)); }
  }
  return null;
}

function pickScore(metrics) {
  const order = ["cvssMetricV40", "cvssMetricV31", "cvssMetricV30", "cvssMetricV2"];
  for (const k of order) {
    const arr = metrics?.[k];
    if (Array.isArray(arr) && arr.length) {
      const best = arr.map((m) => m.cvssData || {}).sort((a, b) => (b.baseScore || 0) - (a.baseScore || 0))[0];
      if (best && typeof best.baseScore === "number") {
        return { score: best.baseScore, vector: best.vectorString || "", ver: (best.version || (k === "cvssMetricV40" ? "4.0" : k === "cvssMetricV2" ? "2.0" : "3.x")) };
      }
    }
  }
  return null;
}

(async () => {
  let cursor = new Date(START);
  let totalKept = 0, totalSeen = 0;
  const manifest = [];
  while (cursor < END) {
    const winEnd = new Date(Math.min(cursor.getTime() + WIN_DAYS * 86400000, END.getTime()));
    const tag = cursor.toISOString().slice(0, 10) + "_" + winEnd.toISOString().slice(0, 10);
    const file = path.join(RAW, "win-" + tag + ".json");
    if (!fs.existsSync(file)) {
      const kept = [];
      let startIndex = 0, total = Infinity, pages = 0;
      while (startIndex < total && pages < 60) {
        const url = "https://services.nvd.nist.gov/rest/json/cves/2.0?pubStartDate=" + encodeURIComponent(iso(cursor)) +
          "&pubEndDate=" + encodeURIComponent(iso(winEnd)) + "&resultsPerPage=" + PAGE + "&startIndex=" + startIndex;
        const j = await api(url);
        if (!j) { log("FAIL window", tag, "at", startIndex); break; }
        total = j.totalResults; pages++;
        for (const v of j.vulnerabilities || []) {
          totalSeen++;
          if (v.cve.vulnStatus === "Rejected") continue;
          const sc = pickScore(v.cve.metrics);
          if (!sc || sc.score < 4.0) continue;
          const desc = (v.cve.descriptions || []).find((d) => d.lang === "en")?.value || "";
          const cwe = [...new Set((v.cve.weaknesses || []).flatMap((w) => (w.description || []).filter((d) => /^CWE-/.test(d.value)).map((d) => d.value)))];
          const cpe = (v.cve.configurations || []).flatMap((c) => (c.nodes || []).flatMap((nd) =>
            (nd.cpeMatch || []).map((m) => m.criteria).concat((nd.children || []).flatMap((ch) => (ch.cpeMatch || []).map((m) => m.criteria))))).slice(0, 24);
          kept.push({
            id: v.cve.id, published: v.cve.published, lastModified: v.cve.lastModified,
            score: sc.score, severity: sc.score >= 9 ? "critical" : sc.score >= 7 ? "high" : sc.score >= 4 ? "medium" : "low",
            vector: sc.vector, cvssVer: sc.ver, cwe, desc, refs: (v.cve.references || []).length,
            cpe,
          });
        }
        startIndex += PAGE;
        log("page", tag, startIndex + "/" + total, "kept", kept.length);
        if (startIndex < total) await sleep(GAP);
      }
      fs.writeFileSync(file, JSON.stringify(kept));
      totalKept += kept.length;
      manifest.push({ window: tag, kept: kept.length, total });
      log("WINDOW DONE", tag, "kept", kept.length, "nvdTotal", total, "cumKept", totalKept);
      fs.writeFileSync(path.join(RAW, "manifest.json"), JSON.stringify(manifest, null, 1));
    } else {
      const k = JSON.parse(fs.readFileSync(file, "utf8"));
      totalKept += k.length;
      manifest.push({ window: tag, kept: k.length, cached: true });
      log("WINDOW CACHED", tag, k.length, "cumKept", totalKept);
    }
    cursor = winEnd;
    await sleep(GAP);
  }
  log("ALL DONE seen=" + totalSeen + " kept=" + totalKept);
})();
