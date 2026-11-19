"use client";

import * as React from "react";

import { ExternalLinkIcon, SearchIcon, ShieldAlertIcon } from "lucide-react";

import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { http } from "@/lib/api";

interface CVE {
  id: string;
  score: number;
  severity: string;
  cwe: string;
  published: string;
  vendor: string;
  product: string;
  title: string;
  desc: string;
  refs: number;
  tags: string;
}
interface SearchResp {
  results: CVE[];
  total: number;
}
interface StatsResp {
  total: number;
  by_severity: Record<string, number>;
}

const SEV_CLASS: Record<string, string> = {
  critical: "bg-red-600 text-white",
  high: "bg-orange-500 text-white",
  medium: "bg-amber-500 text-black",
  low: "bg-sky-500 text-white",
};
function sevClass(s: string): string {
  return SEV_CLASS[(s || "").toLowerCase()] ?? "bg-muted text-foreground";
}

export default function CVEPage() {
  const [q, setQ] = React.useState("");
  const [severity, setSeverity] = React.useState("");
  const [minScore, setMinScore] = React.useState(0);
  const [results, setResults] = React.useState<CVE[]>([]);
  const [total, setTotal] = React.useState(0);
  const [stats, setStats] = React.useState<StatsResp | null>(null);
  const [selected, setSelected] = React.useState<CVE | null>(null);
  const [loading, setLoading] = React.useState(false);

  const search = React.useCallback(async () => {
    setLoading(true);
    try {
      const p = new URLSearchParams();
      if (q) p.set("q", q);
      if (severity) p.set("severity", severity);
      if (minScore > 0) p.set("min_score", String(minScore));
      p.set("limit", "50");
      const r = await http<SearchResp>(`/cve/search?${p.toString()}`);
      setResults(r.results ?? []);
      setTotal(r.total ?? 0);
    } catch {
      setResults([]);
      setTotal(0);
    } finally {
      setLoading(false);
    }
  }, [q, severity, minScore]);

  React.useEffect(() => {
    http<StatsResp>("/cve/stats")
      .then(setStats)
      .catch(() => {});
    void search();
  }, [search]);

  return (
    <div className="flex flex-col gap-4 p-4 md:p-6">
      <Card>
        <CardHeader>
          <CardTitle className="flex items-center gap-2">
            <ShieldAlertIcon className="size-5" /> CVE 知识库
          </CardTitle>
          <CardDescription>
            {stats
              ? `共 ${stats.total.toLocaleString()} 条 · 严重 ${stats.by_severity.critical ?? 0} / 高危 ${stats.by_severity.high ?? 0} / 中危 ${stats.by_severity.medium ?? 0}`
              : "加载中…"}
          </CardDescription>
        </CardHeader>
        <CardContent className="flex flex-col gap-3 md:flex-row md:items-end">
          <div className="flex-1">
            <Input
              placeholder="搜索 CVE / 厂商 / 关键词（如 apache tomcat）"
              value={q}
              onChange={(e) => setQ(e.target.value)}
              onKeyDown={(e) => {
                if (e.key === "Enter") void search();
              }}
            />
          </div>
          <select
            className="h-9 rounded-md border bg-background px-3 text-sm"
            value={severity}
            onChange={(e) => setSeverity(e.target.value)}
          >
            <option value="">全部严重度</option>
            <option value="critical">严重</option>
            <option value="high">高危</option>
            <option value="medium">中危</option>
            <option value="low">低危</option>
          </select>
          <label className="flex items-center gap-2 text-sm whitespace-nowrap">
            CVSS ≥ {minScore}
            <input
              type="range"
              min={0}
              max={10}
              step={0.5}
              value={minScore}
              onChange={(e) => setMinScore(Number(e.target.value))}
              className="w-28"
            />
          </label>
          <Button onClick={() => void search()} disabled={loading}>
            <SearchIcon className="size-4" /> 搜索
          </Button>
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle className="text-base">结果 {total ? `· ${total.toLocaleString()}` : ""}</CardTitle>
        </CardHeader>
        <CardContent>
          <div className="-mx-3 overflow-x-auto px-3">
            <Table className="min-w-[640px]">
              <TableHeader>
                <TableRow>
                  <TableHead className="sticky left-0 z-10 bg-background">CVE</TableHead>
                  <TableHead>严重度</TableHead>
                  <TableHead>CVSS</TableHead>
                  <TableHead>厂商</TableHead>
                  <TableHead>标题</TableHead>
                  <TableHead>发布</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {results.map((c) => (
                  <TableRow key={c.id} className="cursor-pointer" onClick={() => setSelected(c)}>
                    <TableCell className="sticky left-0 z-10 bg-background font-mono text-xs">{c.id}</TableCell>
                    <TableCell>
                      <Badge className={sevClass(c.severity)}>{c.severity || "-"}</Badge>
                    </TableCell>
                    <TableCell>{(c.score ?? 0).toFixed(1)}</TableCell>
                    <TableCell>{c.vendor}</TableCell>
                    <TableCell className="max-w-[320px] truncate">{c.title}</TableCell>
                    <TableCell className="text-xs text-muted-foreground">{c.published}</TableCell>
                  </TableRow>
                ))}
                {results.length === 0 && (
                  <TableRow>
                    <TableCell colSpan={6} className="py-8 text-center text-muted-foreground">
                      {loading ? "搜索中…" : "无结果"}
                    </TableCell>
                  </TableRow>
                )}
              </TableBody>
            </Table>
          </div>
        </CardContent>
      </Card>

      {selected && (
        <Card>
          <CardHeader>
            <CardTitle className="flex flex-wrap items-center gap-2 font-mono">
              {selected.id}
              <Badge className={sevClass(selected.severity)}>{selected.severity}</Badge>
              <span className="text-sm text-muted-foreground">CVSS {(selected.score ?? 0).toFixed(1)}</span>
            </CardTitle>
            <CardDescription>{selected.title}</CardDescription>
          </CardHeader>
          <CardContent className="flex flex-col gap-3 text-sm">
            <section>
              <h4 className="mb-1 font-medium">针对什么</h4>
              <p className="text-muted-foreground">
                {selected.vendor} / {selected.product} · {selected.cwe || "CWE 未分类"}
              </p>
            </section>
            <section>
              <h4 className="mb-1 font-medium">描述</h4>
              <p className="whitespace-pre-wrap text-muted-foreground">{selected.desc}</p>
            </section>
            {selected.tags && (
              <section>
                <h4 className="mb-1 font-medium">相关技能</h4>
                <div className="flex flex-wrap gap-1">
                  {selected.tags
                    .split(",")
                    .filter(Boolean)
                    .map((t) => (
                      <Badge key={t} variant="secondary">
                        {t}
                      </Badge>
                    ))}
                </div>
              </section>
            )}
            <section className="flex flex-wrap items-center gap-3 text-muted-foreground">
              <span>发布 {selected.published}</span>
              <span>引用 {selected.refs}</span>
              <a
                className="inline-flex items-center gap-1 text-primary hover:underline"
                href={`https://nvd.nist.gov/vuln/detail/${selected.id}`}
                target="_blank"
                rel="noreferrer"
              >
                NVD <ExternalLinkIcon className="size-3" />
              </a>
            </section>
          </CardContent>
        </Card>
      )}
    </div>
  );
}
