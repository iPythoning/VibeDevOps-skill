#!/bin/bash
# check-feature-map —— 让 feature map 不能悄悄过期（ADR 0011 地图层的守卫）。
#
# 过期的地图比没有地图更危险：没有地图 agent 会去读代码，过期的地图会让它
# **自信地走到错误的地方**。所以这道校验进 PR 门禁：改了路由没改地图即红。
#
# 校验三件事（都只用仓库内事实，不联网）：
#   1. 地图里每个 route 都在路由真相源里存在
#   2. 地图里每个 components 文件都存在（改名/删除会被抓到）
#   3. 地图里每个 i18n_prefix 在 i18n 文件里存在（文案树重构会被抓到）
# 反向不强制（路由多于地图只警告）——新路由未必都是需要验证的功能面。
#
# 用法：check-feature-map.sh [--map FILE] [--repo DIR] [--strict]
#   --strict：路由表里有而地图里没有的，也算失败
set -euo pipefail

MAP="${FEATURE_MAP:-docs/feature-map.yaml}"; REPO="."; STRICT=0
while [ "$#" -gt 0 ]; do
  case "$1" in
    --map) MAP=$2; shift 2 ;;
    --repo) REPO=$2; shift 2 ;;
    --strict) STRICT=1; shift ;;
    -h|--help) sed -n '2,16p' "$0"; exit 0 ;;
    *) echo "未知参数: $1" >&2; exit 2 ;;
  esac
done
cd "$REPO"
[ -f "$MAP" ] || { echo "❌ 找不到 feature map: $MAP（模板见 templates/verification/feature-map.template.yaml）" >&2; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "❌ 需要 python3" >&2; exit 3; }

python3 - "$MAP" "$STRICT" << 'PYEOF'
import json, os, re, sys
try:
    import yaml
except ImportError:
    print("❌ 需要 pyyaml（pip install pyyaml）", file=sys.stderr); sys.exit(3)

map_path, strict = sys.argv[1], sys.argv[2] == "1"
m = yaml.safe_load(open(map_path))
meta, features = m.get("meta") or {}, m.get("features") or []
fails, warns = [], []

# ── 1. 路由存在性 + 路由↔组件对应 ──
# 只验「路由存在」不够：路由表里可能同时有 /messages 与 /inbox，地图写错一个
# 照样通过，而 agent 会被带到另一个页面（实测踩过）。所以连 element 一起提。
router = meta.get("router_file")
routes_in_code = set()
route_to_element = {}
if router and os.path.exists(router):
    src = open(router, encoding="utf-8", errors="ignore").read()
    for raw in re.findall(r'path="([^"]*)"', src):
        routes_in_code.add("/" + raw.strip("/") if raw else "/")
    # <Route path="inbox" element={<Inbox />} /> → {/inbox: Inbox}
    for raw, elem in re.findall(r'path="([^"]*)"\s+element=\{<\s*([A-Za-z0-9_]+)', src):
        route_to_element["/" + raw.strip("/") if raw else "/"] = elem
elif router:
    fails.append(f"router_file 不存在: {router}")

def route_covered(route):
    """地图 route 可以是页面内 tab（/app/settings），只要其路径段在路由表里能对上即可。"""
    tail = "/" + route.strip("/").split("/")[-1]
    return any(r == route or r.endswith(tail) or route.endswith(r.strip("/")) for r in routes_in_code)

for f in features:
    name = f.get("name", "?")
    r = f.get("route")
    if routes_in_code and r and not route_covered(r):
        fails.append(f"[{name}] route {r} 在 {router} 里找不到——路由改了没改地图？")
    # ── 2. 组件文件存在性 + 与路由指向一致 ──
    comps = f.get("components") or []
    for c in comps:
        if not os.path.exists(c):
            fails.append(f"[{name}] 组件文件不存在: {c}")
    if r and route_to_element and comps:
        tail = "/" + r.strip("/").split("/")[-1]
        elem = route_to_element.get(r) or route_to_element.get(tail)
        if elem:
            basenames = {os.path.splitext(os.path.basename(c))[0] for c in comps}
            if elem not in basenames:
                fails.append(
                    f"[{name}] route {r} 指向组件 <{elem}>，但地图写的是 {sorted(basenames)}"
                    f"——路由写对了、组件对不上，agent 会被带到另一个页面")
    # ── 3. i18n 前缀存在性 ──
    pref = f.get("i18n_prefix")
    if pref:
        found = False
        for i18n in (meta.get("i18n_files") or []):
            if not os.path.exists(i18n):
                continue
            try:
                d = json.load(open(i18n, encoding="utf-8"))
            except Exception:
                continue
            node = d
            for part in pref.split("."):
                if isinstance(node, dict) and part in node:
                    node = node[part]
                else:
                    node = None; break
            if node is not None:
                found = True; break
        if not found:
            fails.append(f"[{name}] i18n_prefix '{pref}' 在 i18n 文件里不存在——文案树重构了？")

# ── strict：路由多于地图 ──
if strict and routes_in_code:
    mapped = {f.get("route") for f in features if f.get("route")}
    skip = re.compile(r':|login|callback|reset-password|magic|oauth|success|^/$')
    for r in sorted(routes_in_code):
        if skip.search(r):
            continue
        if not any(r == mm or (mm and r.endswith(mm.strip('/').split('/')[-1])) for mm in mapped):
            warns.append(f"路由 {r} 没有出现在 feature map 里")

for w in warns:
    print(f"⚠ {w}")
if fails:
    for x in fails:
        print(f"❌ {x}", file=sys.stderr)
    print(f"\nfeature map 与代码不一致（{len(fails)} 处）。地图过期会让 agent 自信地走错——先修地图。", file=sys.stderr)
    sys.exit(1)
if strict and warns:
    print(f"\n--strict：{len(warns)} 个路由未入图", file=sys.stderr); sys.exit(1)
print(f"✅ feature map 一致：{len(features)} 个功能，路由/组件/i18n 前缀全部对得上")
PYEOF
