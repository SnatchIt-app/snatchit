"use client";
import{useActionState}from"react";
import{Button}from"@astryxdesign/core";
import{Alert}from"@/components/ui/Alert";
import{archiveOldListings,checkListingArchiveConnection,type ListingArchiveState}from"@/lib/listing-archive-actions";
import{LISTING_ARCHIVE_CONFIRMATION}from"@/lib/listing-archive";
export function ListingArchiveForm({digest}:{digest:string}){const[state,action,pending]=useActionState<ListingArchiveState,FormData>(archiveOldListings,{});const[check,checkAction,checking]=useActionState<ListingArchiveState>(checkListingArchiveConnection,{});return<><form action={checkAction} className="mt-4"><Button type="submit" label="Run archive safety check" isLoading={checking} isDisabled={pending||checking}/>{check.checked?<Alert state="success" title="The full archive safety check passed. All attempted changes were rolled back."/>:null}{check.error?<Alert state="failed" title={check.error}/>:null}</form><form action={action}className="mt-5 space-y-4">
 <input type="hidden"name="digest"value={digest}/>
 <label className="block text-sm">Cleanup reason<textarea name="reason"required minLength={15}maxLength={2000}className="field mt-1"rows={3}disabled={pending||state.completed}/></label>
 <label className="block text-sm">Type <strong>{LISTING_ARCHIVE_CONFIRMATION}</strong> to confirm<input name="confirmation"required autoComplete="off"className="field mt-1"disabled={pending||state.completed}/></label>
 <Button type="submit"label="Archive the 113 older listings"isDisabled={pending||state.completed}isLoading={pending}/>
 {state.error?<Alert state="failed"title={state.error}/>:null}{state.completed?<Alert state="success"title="The older listings are archived. The five kept listings are unchanged."/>:null}
 </form></>;}
