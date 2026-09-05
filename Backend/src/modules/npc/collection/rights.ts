export function plainText(value: string): string {
  return value
    .replace(/<[^>]*>/gu, " ")
    .replace(/&amp;/gu, "&")
    .replace(/&quot;/gu, '"')
    .replace(/&#39;|&apos;/gu, "'")
    .replace(/&nbsp;/gu, " ")
    .replace(/\s+/gu, " ")
    .trim()
    .slice(0, 2000);
}
export function screenCommonsLicense(
  label: string,
  url: string | null,
  restrictions: string,
): boolean {
  if (!url || restrictions.trim()) return false;
  const parsed = new URL(url);
  if (
    parsed.protocol !== "https:" ||
    parsed.hostname !== "creativecommons.org" ||
    parsed.port ||
    parsed.hash ||
    parsed.search ||
    parsed.username ||
    parsed.password
  )
    return false;
  const path = parsed.pathname.replace(/\/$/u, "");
  return (
    (label === "CC0" && path === "/publicdomain/zero/1.0") ||
    ["2.0", "2.5", "3.0", "4.0"].some(
      (version) => label === `CC BY ${version}` && path === `/licenses/by/${version}`,
    )
  );
}
