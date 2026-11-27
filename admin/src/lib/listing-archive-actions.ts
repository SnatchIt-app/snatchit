"use server";
import{revalidatePath}from"next/cache";
import{requireOperator}from"@/lib/auth/session";
import{callOps}from"@/lib/ops";
import{listingArchiveArgs,listingArchiveReceipt}from"@/lib/listing-archive";
export type ListingArchiveState={error?:string;completed?:boolean};
export async function archiveOldListings(_previous:ListingArchiveState,form:FormData):Promise<ListingArchiveState>{
 const me=await requireOperator();if(me.role!=="platform_admin")return{error:"Only a platform admin can run this cleanup."};
 const args=listingArchiveArgs(form);if(!args)return{error:"Enter the exact confirmation and a reason of 15–2,000 characters."};
 const r=await callOps<unknown>("prelaunch_listing_execute",args);if(!r.ok)return{error:"Cleanup was not confirmed. Refresh to check the archive; no success is assumed."};
 if(!listingArchiveReceipt(r.data,args.p_digest))return{error:"The archive receipt could not be verified. Refresh before doing anything else."};
 for(const p of["/system/listing-archive","/marketplace","/users","/system","/"])revalidatePath(p);
 return{completed:true};
}
