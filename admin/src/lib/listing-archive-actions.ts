"use server";
import{revalidatePath}from"next/cache";
import{requireOperator}from"@/lib/auth/session";
import{callOps}from"@/lib/ops";
import{listingArchiveArgs,listingArchiveReceipt}from"@/lib/listing-archive";
export type ListingArchiveState={error?:string;completed?:boolean;checked?:boolean};
function failureMessage(r:import("@/lib/ops-errors").OpsFailure):string{
 if(r.kind==="mfa")return "Your two-step verification expired. Verify your sign-in again, then return here.";
 if(r.kind==="denied")return "Your sign-in does not have permission for this cleanup. A platform admin must review it.";
 if(r.kind==="paused")return "Console changes are paused. The archive has not been confirmed.";
 if(r.kind==="error"&&r.code==="P0001"&&r.message==="catalog_archive_refused: source changed since backup")return "Records changed after the backup. A fresh review is required; refreshing alone will not fix it.";
 if(r.kind==="error"&&r.code==="21000")return "The database refused the archive because a request expected one result. No cleanup was confirmed. Reference: 21000.";
 return "Cleanup was not confirmed. Refresh to check the archive; no success is assumed.";
}
/** An impossible digest fails before archive changes and table locks; never a retry of the cleanup. */
export async function checkListingArchiveConnection():Promise<ListingArchiveState>{
 const me=await requireOperator();if(me.role!=="platform_admin")return{error:"Only a platform admin can check this cleanup."};
 const r=await callOps<unknown>("prelaunch_listing_execute",{p_digest:"",p_reason:"Connection diagnostic only; never execute archive",p_confirmation:"ARCHIVE 113 OLD LISTINGS"});
 if(!r.ok&&r.kind==="error"&&r.code==="P0001"&&r.message==="catalog_archive_refused: verified backup required")return{checked:true};
 return{error:r.ok?"Unexpected response. No cleanup success is assumed.":failureMessage(r)};
}
export async function archiveOldListings(_previous:ListingArchiveState,form:FormData):Promise<ListingArchiveState>{
 const me=await requireOperator();if(me.role!=="platform_admin")return{error:"Only a platform admin can run this cleanup."};
 const args=listingArchiveArgs(form);if(!args)return{error:"Enter the exact confirmation and a reason of 15–2,000 characters."};
 const r=await callOps<unknown>("prelaunch_listing_execute",args);if(!r.ok)return{error:failureMessage(r)};
 if(!listingArchiveReceipt(r.data,args.p_digest))return{error:"The archive receipt could not be verified. Refresh before doing anything else."};
 for(const p of["/system/listing-archive","/marketplace","/users","/system","/"])revalidatePath(p);
 return{completed:true};
}
