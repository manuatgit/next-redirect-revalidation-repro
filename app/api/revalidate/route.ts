import { revalidateTag } from 'next/cache';

// Marks every entry tagged "redirects" as stale (stale-while-revalidate).
export async function POST() {
  revalidateTag('redirects', 'max');
  return Response.json({ revalidated: true });
}
