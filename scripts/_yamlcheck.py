import yaml, sys
try:
    d = yaml.safe_load(open(r"E:/ds/ARTEXX-iOS/.github/workflows/build-ipa.yml", encoding="utf-8"))
    print("YAML OK, jobs:", list(d.get("jobs", {}).keys()))
    steps = d["jobs"]["build"]["steps"]
    print("steps:", len(steps))
    for s in steps:
        print(" -", s.get("name"))
except Exception as e:
    print("YAML FAIL:", e); sys.exit(1)
