#!/usr/bin/env bash
# Reproduces: a cached page that becomes a permanentRedirect() during a
# background (stale-while-revalidate) revalidation is cached as 308 without
# a Location header.
set -euo pipefail
cd "$(dirname "$0")"
PORT=3123
BASE="http://localhost:$PORT"

head_of() { # status line + location headers only
  curl -s -o /dev/null -D - "$BASE$1" | tr -d '\r' | grep -iE '^(HTTP/|location:|x-nextjs-cache:)' | sed 's/^/    /'
}

echo '{}' > data/redirects.json
rm -rf .next
npx next build > build.log 2>&1 || { cat build.log; exit 1; }

npx next start -p "$PORT" > start.log 2>&1 &
SERVER=$!
trap 'kill $SERVER 2>/dev/null || true' EXIT
until curl -s -o /dev/null "$BASE/target"; do sleep 0.3; done

echo "== 1. /foo is a normal page (rendered and cached)"
head_of /foo
head_of /foo

echo "== 2. data changes: /foo should now redirect to /target; revalidateTag('redirects', 'max')"
echo '{"foo": "/target"}' > data/redirects.json
curl -s -X POST "$BASE/api/revalidate" > /dev/null

echo "== 3. first request: stale page served, background revalidation starts"
head_of /foo
sleep 2

echo "== 4. following requests: served from the regenerated cache entry"
head_of /foo
head_of /foo
echo "    body: $(curl -s "$BASE/foo" | grep -o 'NEXT_REDIRECT;[^"\\]*' | head -1)"

echo "== 5. (separate, minor) /bar is a redirect on its very first render: Location is sent twice"
echo '{"foo": "/target", "bar": "/target"}' > data/redirects.json
head_of /bar
head_of /bar

echo "== 6. destination of the already cached /bar changes to /target?v=2; revalidateTag('redirects', 'max')"
echo '{"foo": "/target", "bar": "/target?v=2"}' > data/redirects.json
curl -s -X POST "$BASE/api/revalidate" > /dev/null
head_of /bar
sleep 2
head_of /bar
echo "    body: $(curl -s "$BASE/bar" | grep -o 'NEXT_REDIRECT;[^"\\]*' | head -1)"

echo "== cache entries (.meta) for /foo and /bar:"
for f in foo bar; do
  META=$(find .next/server -name "$f.meta" | head -1)
  if [ -n "$META" ]; then echo "    $f: $(node -e 'const m=JSON.parse(require("fs").readFileSync(process.argv[1],"utf8"));console.log(JSON.stringify({status:m.status,location:m.headers.location}))' "$META")"; fi
done
