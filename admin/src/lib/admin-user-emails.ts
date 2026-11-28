import "server-only";
import { callOps } from "@/lib/ops";
import type { OperatorRole } from "@/lib/types";
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
export type EmailLookup = { state: "masked" } | { state: "unavailable" } | { state: "ready"; emails: Record<string,string|null> };
export function parseAdminUserEmails(value: unknown, expectedIds: string[]): Record<string,string|null> | null {
  const expected = new Set(expectedIds.map(id=>id.toLowerCase()));
  if (expected.size>200 || expectedIds.some(id=>!UUID.test(id)) || !Array.isArray(value) || value.length!==expected.size) return null;
  const emails: Record<string,string|null> = {};
  for (const item of value) {
    if (!item || typeof item!=="object" || Array.isArray(item)) return null;
    const row=item as Record<string,unknown>;
    if (typeof row.id!=="string" || !UUID.test(row.id)) return null;
    const id=row.id.toLowerCase();
    if (!expected.has(id) || Object.prototype.hasOwnProperty.call(emails,id)) return null;
    if (row.email!==null && (typeof row.email!=="string" || row.email.length>320 || !row.email.includes("@") || /[\r\n\x00]/.test(row.email))) return null;
    emails[id]=row.email as string|null;
  }
  return emails;
}
/** Per request, using the operator's own JWT. The database independently checks admin+MFA. */
export async function getAdminUserEmails(role: OperatorRole, ids: string[]): Promise<EmailLookup> {
  if (role!=="platform_admin") return {state:"masked"};
  if (!ids.length) return {state:"ready",emails:{}};
  const result=await callOps<unknown>("admin_user_emails",{p_user_ids:ids});
  if (!result.ok) return {state:"unavailable"};
  const emails=parseAdminUserEmails(result.data,ids);
  return emails ? {state:"ready",emails} : {state:"unavailable"};
}
