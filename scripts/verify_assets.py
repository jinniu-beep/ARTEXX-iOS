#!/usr/bin/env python3
"""校验内置于 App 的知识库资源完整性（CI 与本地都可跑）。"""
import gzip
import json
import os
import sqlite3
import sys
import tempfile

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "ios", "ARTEXX", "Resources")
SKILLS = os.path.join(ROOT, "skills.json")
CVEGZ = os.path.join(ROOT, "cve.sqlite.gz")
EXPLOITS = os.path.join(ROOT, "exploits.json")

fail = []

def check(cond, msg):
    print(("  OK  " if cond else "  FAIL ") + msg)
    if not cond:
        fail.append(msg)

print("== 资源校验:", ROOT)
for p in (SKILLS, CVEGZ, EXPLOITS):
    check(os.path.exists(p), "存在 " + os.path.basename(p))

if os.path.exists(SKILLS):
    skills = json.load(open(SKILLS, encoding="utf-8"))
    ids = [s["id"] for s in skills]
    cats = sorted({s["cat"] for s in skills})
    check(len(skills) >= 300, "技能条数 >= 300（实际 %d）" % len(skills))
    check(len(set(ids)) == len(ids), "技能 id 无重复")
    check(len(cats) >= 10, "技能分类 >= 10（实际 %d：%s）" % (len(cats), ",".join(cats)))
    no_cmd = [s["id"] for s in skills if not s.get("cmds")]
    check(not no_cmd, "每条技能都有命令（缺失 %d）" % len(no_cmd))

if os.path.exists(EXPLOITS):
    exp = json.load(open(EXPLOITS, encoding="utf-8"))
    check(len(exp) >= 5000, "ExploitDB 索引 CVE 数 >= 5000（实际 %d）" % len(exp))

if os.path.exists(CVEGZ):
    tmp = tempfile.mktemp(suffix=".sqlite")
    with gzip.open(CVEGZ, "rb") as f, open(tmp, "wb") as o:
        while True:
            b = f.read(1 << 20)
            if not b:
                break
            o.write(b)
    con = sqlite3.connect(tmp)
    n = con.execute("select count(*) from cve").fetchone()[0]
    sev = dict(con.execute("select severity, count(*) from cve group by severity"))
    cols = [r[1] for r in con.execute("pragma table_info(cve)")]
    check(n >= 5000, "CVE 条数 >= 5000（实际 %d）" % n)
    check(sev.get("critical", 0) > 0 and sev.get("high", 0) > 0, "包含 critical/high 分级 %s" % sev)
    check("guidance" in cols, "含 guidance 列（可展开攻击指引）")
    try:
        con.execute("select count(*) from cve_fts where cve_fts match 'apache'").fetchone()
        check(True, "FTS5 索引可用")
    except Exception as e:
        check(False, "FTS5 索引不可用: %s" % e)
    con.close()
    os.unlink(tmp)

print("== 结果:", "全部通过" if not fail else "失败项 %d" % len(fail))
sys.exit(1 if fail else 0)
