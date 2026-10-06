#!/usr/bin/env bash
# Match owner text to live categories/brands. Never creates taxonomy. Docker DNS only.
set -euo pipefail

KIND=""
QUERY=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --kind) KIND="${2:-}"; shift 2 ;;
    --query) QUERY="${2:-}"; shift 2 ;;
    -h|--help)
      echo "Usage: $0 --kind category|brand --query TEXT" >&2
      exit 0
      ;;
    *)
      echo "Unknown arg: $1" >&2
      exit 2
      ;;
  esac
done

if [[ "$KIND" != "category" && "$KIND" != "brand" ]]; then
  echo "Usage: $0 --kind category|brand --query TEXT" >&2
  exit 2
fi
if [[ -z "${QUERY// }" ]]; then
  echo '{"ok":false,"error":"query is required"}'
  exit 1
fi

API_BASE="${SHOP_API_PUBLIC:-http://backend:8080/api}"
case "$API_BASE" in
  *127.0.0.1*|*localhost*|*[::1]*)
    API_BASE="http://backend:8080/api"
    ;;
esac

if [[ "$KIND" == "category" ]]; then
  URL="${API_BASE}/Categories?page=1&pageSize=100&onlyActives=true"
else
  URL="${API_BASE}/Brands?page=1&pageSize=100&onlyActives=true"
fi

RAW="$(curl -sS "$URL")"
QUERY="$QUERY" KIND="$KIND" RAW="$RAW" python3 - <<'PY'
import json, os, re, unicodedata

raw = os.environ["RAW"]
kind = os.environ["KIND"]
query = os.environ["QUERY"].strip()

try:
    payload = json.loads(raw)
except Exception as e:
    print(json.dumps({"ok": False, "error": f"invalid taxonomy JSON: {e}"}, ensure_ascii=False))
    raise SystemExit(1)

data = payload.get("data") if isinstance(payload, dict) else payload
records = []
if isinstance(data, dict):
    records = data.get("records") or data.get("Records") or []
elif isinstance(data, list):
    records = data

ALIASES = {
    "پریزماتیگ": "پریزماتیک",
    "پریزمی": "پریزماتیک",
    "گالیلی": "گالیله‌ای",
    "گالیله": "گالیله‌ای",
    "لوپه": "لوپ",
    "loupe": "لوپ",
    "headlight": "هدلایت",
}


def norm(s: str) -> str:
    s = unicodedata.normalize("NFKC", s or "")
    s = s.replace("ي", "ی").replace("ك", "ک").replace("ۀ", "ه").replace("ة", "ه")
    s = s.replace("‌", " ").replace("-", " ")
    s = re.sub(r"\s+", " ", s).strip().casefold()
    return s


def expand(q: str) -> list[str]:
    n = norm(q)
    out = {n}
    for a, b in ALIASES.items():
        an, bn = norm(a), norm(b)
        if n == an or an in n or n in an:
            out.add(bn)
            out.add(an)
        if bn in n or n in bn:
            out.add(bn)
            out.add(an)
    # also replace alias tokens inside query
    tokens = n.split()
    for i, t in enumerate(tokens):
        if t in {norm(k) for k in ALIASES}:
            for a, b in ALIASES.items():
                if norm(a) == t:
                    alt = tokens[:]
                    alt[i] = norm(b)
                    out.add(" ".join(alt))
    return [x for x in out if x]


def item_name(rec: dict) -> str:
    if kind == "category":
        return str(rec.get("persianName") or rec.get("englishName") or rec.get("name") or "")
    return str(rec.get("name") or rec.get("persianName") or "")


def score(qvars: list[str], name: str) -> int:
    nn = norm(name)
    if not nn:
        return -1
    best = 0
    for q in qvars:
        if not q:
            continue
        if nn == q:
            best = max(best, 100)
        elif q in nn:
            best = max(best, 80 + min(15, len(q)))
        elif nn in q:
            best = max(best, 70)
        else:
            # token overlap
            qt, nt = set(q.split()), set(nn.split())
            if qt and nt:
                overlap = len(qt & nt)
                if overlap:
                    best = max(best, 40 + overlap * 10)
    return best


qvars = expand(query)
scored = []
for rec in records:
    if not isinstance(rec, dict):
        continue
    if rec.get("isActive") is False:
        continue
    name = item_name(rec)
    s = score(qvars, name)
    if s <= 0:
        continue
    scored.append({
        "id": rec.get("id"),
        "name": name,
        "score": s,
        "kind": kind,
    })

scored.sort(key=lambda x: (-x["score"], x["id"] or 0))
top = scored[:8]
best = top[0] if top else None
ambiguous = len(top) >= 2 and top[0]["score"] == top[1]["score"] and top[0]["score"] >= 70

print(json.dumps({
    "ok": True,
    "kind": kind,
    "query": query,
    "normalizedQueries": qvars,
    "created": False,
    "matchCount": len(top),
    "best": best,
    "ambiguous": ambiguous,
    "matches": top,
    "hint": (
        "no live match — ask owner to pick from list-taxonomy; never create category/brand"
        if not top else
        ("ambiguous — ask owner which id" if ambiguous else "use best.id only after owner confirmation summary")
    ),
}, ensure_ascii=False))
PY
