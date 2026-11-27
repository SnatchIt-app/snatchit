export const LISTING_ARCHIVE_CONFIRMATION="ARCHIVE 113 OLD LISTINGS";
export const KEPT_LISTINGS=["e4bdc0a7-b7b1-4b2a-a791-677b8c48739d","1add482e-5ffa-41e5-8b9a-592284ec3a17","5bf59649-2a9f-462d-8f48-9f5d3212361f","6ad86aa9-343b-4c54-826f-20dc10c0cc9c","49bd4a3b-20b6-4f60-8f59-c07288ea27df"];
const UUID=/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const HASH=/^[a-f0-9]{64}$/;
export const CATALOG_LABELS={"public.listings":"Older listings","public.bids":"Bids kept in history","public.listing_visibility":"Visibility records","public.saved_listings":"Saved-listing records"};
export type ListingArchive={state:"not_prepared"}|{state:"prepared"|"archived";digest:string;ready:boolean;archived_at:string|null;counts:Record<string,number>;listings:{id:string;event_name:string}[]};
export function parseListingArchive(v:unknown):ListingArchive|null{
 if(!v||typeof v!=="object"||Array.isArray(v))return null;
 const b=v as Record<string,unknown>;
 if(b.state==="not_prepared")return{state:"not_prepared"};
 if(b.state!=="prepared"&&b.state!=="archived"||typeof b.digest!=="string"||!HASH.test(b.digest)||!b.counts||typeof b.counts!=="object"||Array.isArray(b.counts)||!Array.isArray(b.listings)||b.listings.length!==113)return null;
 const counts=b.counts as Record<string,number>;
 if(Object.keys(counts).length!==4||Object.keys(CATALOG_LABELS).some(k=>!Number.isSafeInteger(counts[k])||counts[k]<0)||counts["public.listings"]!==113)return null;
 const seen=new Set<string>();const listings:{id:string;event_name:string}[]=[];
 for(const value of b.listings){if(!value||typeof value!=="object"||Array.isArray(value))return null;const j=value as Record<string,unknown>;if(typeof j.id!=="string"||!UUID.test(j.id)||seen.has(j.id.toLowerCase())||KEPT_LISTINGS.includes(j.id.toLowerCase())||typeof j.event_name!=="string")return null;seen.add(j.id.toLowerCase());listings.push({id:j.id,event_name:j.event_name});}
 if(b.state==="archived"&&(typeof b.archived_at!=="string"||!Number.isFinite(Date.parse(b.archived_at))))return null;
 if(b.state==="prepared"&&b.archived_at!==null)return null;
 return{state:b.state,digest:b.digest,ready:b.ready===true,archived_at:typeof b.archived_at==="string"?b.archived_at:null,counts,listings};
}
export function listingArchiveArgs(form:FormData){const digest=form.get("digest"),reason=form.get("reason"),confirmation=form.get("confirmation");if(typeof digest!=="string"||!HASH.test(digest)||typeof reason!=="string"||reason.trim().length<15||reason.trim().length>2000||confirmation!==LISTING_ARCHIVE_CONFIRMATION)return null;return{p_digest:digest,p_reason:reason.trim(),p_confirmation:confirmation};}
export function listingArchiveReceipt(v:unknown,digest:string):boolean{if(!v||typeof v!=="object"||Array.isArray(v))return false;const r=v as Record<string,unknown>;return r.status==="archived"&&r.digest===digest&&r.listings===113&&r.kept===5;}
