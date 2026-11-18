
// harvest-cve.mjs — 采集 CVE 原始数据（NVD keyword 批量 + CISA KEV + MITRE 补充）
// 输出：resources/cve/raw/*.json
import fs from "node:fs";
import path from "node:path";

const ROOT = path.resolve("E:/ds/ARTEXX-iOS/resources/cve");
const RAW = path.join(ROOT, "raw");
fs.mkdirSync(RAW, { recursive: true });

const log = (...a) => { const s = "[" + new Date().toISOString().slice(11, 19) + "] " + a.join(" "); console.log(s); fs.appendFileSync(path.join(RAW, "harvest.log"), s + "\n"); };
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function getJSON(url, tries = 3, timeout = 60000) {
  for (let i = 0; i < tries; i++) {
    try {
      const ctl = new AbortController();
      const t = setTimeout(() => ctl.abort(), timeout);
      const r = await fetch(url, { signal: ctl.signal, headers: { "User-Agent": "ARTEXX-iOS-CVEHarvester/1.0" } });
      clearTimeout(t);
      if (r.status === 200) return await r.json();
      if (r.status === 403 || r.status === 429 || r.status >= 500) { log("retry", r.status, url.slice(0, 90)); await sleep(8000 * (i + 1)); continue; }
      return null;
    } catch (e) { log("err", String(e.message).slice(0, 80), url.slice(0, 90)); await sleep(5000 * (i + 1)); }
  }
  return null;
}

// ---------- 1. 关键产品关键词 ----------
const KEYWORDS = [
  "nginx","apache http server","apache tomcat","oracle weblogic","ibm websphere","jboss","wildfly","glassfish","eclipse jetty","internet information services","lighttpd","haproxy","traefik",
  "apache struts","spring framework","spring cloud gateway","spring boot","fastjson","jackson databind","xstream","apache log4j","logback","apache shiro","apache dubbo","nacos","apollo config","eureka","sentinel","apache ofbiz","thinkphp","laravel","symfony","codeigniter","django","flask","fastapi","ruby on rails","express","next.js","jquery","angularjs",
  "wordpress","drupal","joomla","magento","prestashop","opencart","typo3","discuz","dedecms","phpcms","ecshop","seacms",
  "jenkins","gitlab","gitea","teamcity","nexus repository","artifactory","sonarqube","harbor","argocd","drone","concourse","ansible","saltstack","puppet","chef","kubernetes","docker","containerd","runc","istio","etcd","consul","vault",
  "mysql","postgresql","oracle database","microsoft sql server","mongodb","redis","memcached","elasticsearch","apache solr","cassandra","couchdb","clickhouse","zookeeper","kafka","rabbitmq","activemq","rocketmq","h2 database","influxdb","neo4j",
  "exchange server","zimbra","roundcube","nextcloud","owncloud","confluence","jira","bitbucket","sharepoint","moodle","openfire","mattermost",
  "fortinet fortios","citrix adc","citrix netscaler","pulse secure","ivanti","f5 big-ip","sonicwall","palo alto networks","cisco adaptive security appliance","juniper","checkpoint","sophos","watchguard","mikrotik routeros","draytek","zyxel","netgear","d-link","tp-link","huawei","h3c","sangfor",
  "seeyon","weaver e-cology","yonyou","landray","tongda oa","ezoffice","kingdee","fanwei","jumpserver",
  "windows smb","remote desktop","netlogon","print spooler","win32k","active directory","vmware vcenter","vmware esxi","vmware workspace one","openstack","proxmox",
  "adobe coldfusion","liferay","dotnetnuke","sitecore","sap netweaver","sap businessobjects","zabbix","grafana","kibana","prometheus","nagios","cacti","phpmyadmin","adminer","webmin","cpanel","plesk","glpi","osTicket",
];

const slug = (s) => s.toLowerCase().replace(/[^a-z0-9]+/g, "-");

async function harvestNVD() {
  let n = 0;
  for (const kw of KEYWORDS) {
    const file = path.join(RAW, "nvd-" + slug(kw) + ".json");
    if (fs.existsSync(file)) { n++; continue; }
    const url = "https://services.nvd.nist.gov/rest/json/cves/2.0?keywordSearch=" + encodeURIComponent(kw) +
      "&cvssV3Severity=CRITICAL,HIGH&noRejected&resultsPerPage=2000";
    const j = await getJSON(url);
    if (!j || !j.vulnerabilities) { log("skip", kw); await sleep(6500); continue; }
    const out = j.vulnerabilities.map((v) => ({
      id: v.cve.id, desc: (v.cve.descriptions || []).find((d) => d.lang === "en")?.value || "",
      published: v.cve.published, lastModified: v.cve.lastModified,
      metrics: v.cve.metrics || {}, weaknesses: v.cve.weaknesses || [],
      refs: (v.cve.references || []).slice(0, 12).map((r) => r.url),
      cpe: (v.cve.configurations || []).flatMap((c) => (c.nodes || []).flatMap((nd) => (nd.cpeMatch || []).map((m) => m.criteria))).slice(0, 20),
      keyword: kw,
    }));
    fs.writeFileSync(file, JSON.stringify(out));
    n++; log("nvd", kw, out.length, "total files", n);
    await sleep(6500);
  }
}

async function harvestKEV() {
  const file = path.join(RAW, "kev.json");
  if (fs.existsSync(file)) { log("kev cached"); return; }
  const j = await getJSON("https://www.cisa.gov/sites/default/files/feeds/known_exploited_vulnerabilities.json");
  if (!j) return;
  fs.writeFileSync(file, JSON.stringify(j.vulnerabilities || []));
  log("kev", (j.vulnerabilities || []).length);
}

async function harvestMITRE(ids) {
  const file = path.join(RAW, "mitre.json");
  const store = fs.existsSync(file) ? JSON.parse(fs.readFileSync(file, "utf8")) : {};
  const todo = ids.filter((id) => !store[id]);
  log("mitre todo", todo.length);
  let done = 0;
  const CONC = 24;
  for (let i = 0; i < todo.length; i += CONC) {
    const batch = todo.slice(i, i + CONC);
    await Promise.all(batch.map(async (id) => {
      const j = await getJSON("https://cveawg.mitre.org/api/cve/" + id, 2, 30000);
      if (!j || !j.containers) return;
      const cna = j.containers.cna || {};
      const adp = (j.containers.adp || []).flatMap((a) => a.problemTypes || []);
      const cwes = [...(cna.problemTypes || []), ...adp].flatMap((p) => (p.descriptions || []).filter((d) => d.cweId).map((d) => d.cweId));
      store[id] = {
        title: cna.title || "",
        desc: (cna.descriptions || [])[0]?.value || "",
        cwe: [...new Set(cwes)],
        refs: (cna.references || []).slice(0, 12).map((r) => r.url),
        state: j.cveMetadata?.state,
      };
    }));
    done += batch.length;
    if (done % 240 === 0) { fs.writeFileSync(file, JSON.stringify(store)); log("mitre", done + "/" + todo.length); }
  }
  fs.writeFileSync(file, JSON.stringify(store));
  log("mitre done", Object.keys(store).length);
}

(async () => {
  await harvestKEV();
  await harvestMITRE([]); // 先跑 KEV 之外的补全由下面统一处理
  await harvestNVD();
  const kev = JSON.parse(fs.readFileSync(path.join(RAW, "kev.json"), "utf8")).map((k) => k.cveID);
  await harvestMITRE(kev);
  log("ALL DONE");
})();
