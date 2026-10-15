# Redirect cached as 308 without `Location` after a background revalidation

Minimal reproduction for a Next.js bug with `cacheComponents: true`.

A dynamic page (`app/[slug]/page.tsx`) reads a cached value (`'use cache'` +
`cacheTag('redirects')`) that decides whether the slug should redirect
(`permanentRedirect()`). The "data source" is `data/redirects.json`.

When a page that is already cached becomes a redirect and the tag is
revalidated with `revalidateTag('redirects', 'max')`, the stale page is served
once and the background revalidation stores a new cache entry with
`status: 308` but **no `location` header**. Every following request gets a
`308` without `Location` (the destination is only in the RSC payload,
`NEXT_REDIRECT;replace;/target;308;`), so crawlers and non-JS clients cannot
follow it.

## Run

```bash
npm install
./repro.sh
```

`repro.sh` builds, starts `next start` on port 3123, then:

1. requests `/foo` (normal page, cached);
2. changes `data/redirects.json` so `/foo` redirects to `/target`, calls
   `POST /api/revalidate` (`revalidateTag('redirects', 'max')`);
3. requests `/foo` (stale page, starts the background revalidation);
4. requests `/foo` again: **308 without `Location`**;
5. requests `/bar`, a redirect on its first render: `Location` sent twice (minor);
6. changes the destination of the cached redirect `/bar`: the cached `Location`
   keeps the **old** destination while the body has the new one;

and prints `status`/`location` of the `.meta` cache entries.

## Output (next 16.4.1)

```
== 4. following requests: served from the regenerated cache entry
    HTTP/1.1 308 Permanent Redirect
    x-nextjs-cache: HIT
    HTTP/1.1 308 Permanent Redirect
    x-nextjs-cache: HIT
    body: NEXT_REDIRECT;replace;/target;308;
...
== 6. destination of the already cached /bar changes to /target?v=2
    HTTP/1.1 308 Permanent Redirect
    x-nextjs-cache: HIT
    location: /target
    body: NEXT_REDIRECT;replace;/target?v=2;308;
== cache entries (.meta) for /foo and /bar:
    foo: {"status":308}
    bar: {"status":308,"location":"/target"}
```

Same result with 16.0.11, 16.3.8, 16.4.0, 16.4.1 and 16.5.0-canary.14.
