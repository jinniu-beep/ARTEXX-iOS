import plistlib, gzip, sqlite3, tempfile, os, json, sys

APP = "E:/ds/ARTEXX-iOS/dist/ex/Payload/ARTEXX.app"
p = plistlib.load(open(os.path.join(APP, "Info.plist"), "rb"))
print("== Info.plist ==")
for k in ["CFBundleIdentifier", "CFBundleDisplayName", "CFBundleShortVersionString",
          "CFBundleVersion", "MinimumOSVersion", "CFBundleSupportedPlatforms", "DTSDKName"]:
    print(" ", k, "=", p.get(k))
print("  ATS 允许任意加载 =", p.get("NSAppTransportSecurity", {}).get("NSAllowsArbitraryLoads"))

print("== 内置资源 ==")
for name in ["skills.json", "cve.sqlite.gz", "exploits.json"]:
    path = os.path.join(APP, name)
    print("  ", name, round(os.path.getsize(path) / 1048576, 2), "MB")

s = json.load(open(os.path.join(APP, "skills.json"), encoding="utf-8"))
print("  技能条数:", len(s), "| 分类:", len({x["cat"] for x in s}))
e = json.load(open(os.path.join(APP, "exploits.json"), encoding="utf-8"))
print("  Exploit 索引 CVE 数:", len(e))

tmp = tempfile.mktemp(suffix=".sqlite")
with gzip.open(os.path.join(APP, "cve.sqlite.gz"), "rb") as f, open(tmp, "wb") as o:
    while True:
        b = f.read(1 << 20)
        if not b:
            break
        o.write(b)
c = sqlite3.connect(tmp)
print("  CVE 条数:", c.execute("select count(*) from cve").fetchone()[0])
print("  分级:", dict(c.execute("select severity,count(*) from cve group by severity")))
row = c.execute("select id,severity,score,vendor,has_exp from cve where id='CVE-2024-3400'").fetchone()
print("  抽样 CVE-2024-3400:", row)
g = c.execute("select guidance from cve where id='CVE-2024-3400'").fetchone()[0]
print("  四段式指引:", g[:220])
print("  FTS 命中 apache tomcat:", c.execute("select count(*) from cve_fts where cve_fts match 'apache AND tomcat'").fetchone()[0])
c.close()
os.unlink(tmp)
print("== OK ==")
