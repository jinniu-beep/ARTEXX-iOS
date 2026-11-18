import gzip, sqlite3, tempfile, os, json, plistlib

APP = "E:/ds/ARTEXX-iOS/dist/ex/Payload/ARTEXX.app"
print("== Info.plist ==")
p = plistlib.load(open(os.path.join(APP, "Info.plist"), "rb"))
for k in ["CFBundleIdentifier", "CFBundleShortVersionString", "MinimumOSVersion", "DTSDKName"]:
    print(" ", k, "=", p.get(k))

# 模拟 App 的解压流程：流式解压 gz -> sqlite，再查完整性
tmp = tempfile.mktemp(suffix=".sqlite")
total = 0
with gzip.open(os.path.join(APP, "cve.sqlite.gz"), "rb") as f, open(tmp, "wb") as o:
    while True:
        b = f.read(1 << 18)
        if not b:
            break
        o.write(b)
        total += len(b)
print("== 解压 ==")
print("  输出字节:", total, "=", round(total / 1048576, 1), "MB")

c = sqlite3.connect(tmp)
n = c.execute("select count(*) from cve").fetchone()[0]
print("  CVE 条数:", n)
print("  分级:", dict(c.execute("select severity,count(*) from cve group by severity")))
print("  FTS:", c.execute("select count(*) from cve_fts where cve_fts match 'apache AND tomcat'").fetchone()[0], "条 apache tomcat")
# 四段式指引抽检
for cve in ["CVE-2023-34362", "CVE-2024-3400"]:
    r = c.execute("select id,severity,score,vendor,has_exp,guidance from cve where id=?", (cve,)).fetchone()
    if r:
        g = json.loads(r[5])
        print("  %s | %s | %.1f | %s | EXP=%s" % (r[0], r[1], r[2], r[3], r[4]))
        print("     类型:", g["type"])
        print("     前提:", g["prereq"][0])
        print("     载荷:", g["payload"][0][:70])
c.close()
os.unlink(tmp)

s = json.load(open(os.path.join(APP, "skills.json"), encoding="utf-8"))
print("== 技能库 ==")
print("  条数:", len(s), "分类:", len({x["cat"] for x in s}))
print("== OK ==")
