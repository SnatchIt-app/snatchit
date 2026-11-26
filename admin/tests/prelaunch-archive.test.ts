import { describe, it, expect } from "vitest";
import { ARCHIVE_CONFIRMATION, buildArchiveArgs, isArchiveReceipt, parseArchiveBatch } from "@/lib/prelaunch-archive";
const ID="aaaaaaaa-0000-4000-8000-000000000001", SHA="a".repeat(64);
const batch=()=>({state:"prepared",id:ID,snapshot_sha256:SHA,backup_verified:true,prepared_at:"2026-11-26T00:00:00Z",expires_at:"2026-11-30T00:00:00Z",archived_at:null,counts:{"public.payments":57,"public.transfers":36},payments:Array.from({length:57},(_,i)=>({id:`00000000-0000-4000-8000-${(i+1).toString(16).padStart(12,"0")}`,created_at:"2026-01-01T00:00:00Z",amount:100,total:110,status:"succeeded",mode:"buy_now"}))});
function form(){const f=new FormData();for(const [k,v] of Object.entries({batch_id:ID,snapshot_sha256:SHA,reason:"Owner-approved pre-launch test cleanup",confirmation:ARCHIVE_CONFIRMATION}))f.set(k,v);return f;}
describe("pre-launch archive boundary",()=>{
 it("accepts the exact reviewed batch",()=>expect(parseArchiveBatch(batch())?.state).toBe("prepared"));
 it.each([null,{},[],{state:"unknown"}])("fails closed on malformed server data %j",v=>expect(parseArchiveBatch(v)).toBeNull());
 it("does not convert missing data into an empty archive",()=>expect(parseArchiveBatch({...batch(),counts:null})).toBeNull());
 it("requires all 57 distinct records",()=>{const b=batch();b.payments[1]=b.payments[0];expect(parseArchiveBatch(b)).toBeNull();expect(parseArchiveBatch({...batch(),payments:[]})).toBeNull();});
 it("refuses either protected payment even with an otherwise valid preview",()=>{for(const id of ["d0508a55-84de-40d8-b696-9e0ea4396bb3","d44d0d3d-90e0-4e3b-a6bd-2769275ec741"]){const b=batch();b.payments[0].id=id;expect(parseArchiveBatch(b)).toBeNull();}});
 it("refuses native custody records",()=>{const b=batch();b.payments[0].mode="native_primary";expect(parseArchiveBatch(b)).toBeNull();});
 it("never interprets a truthy string as a verified backup",()=>expect(parseArchiveBatch({...batch(),backup_verified:"true"})).toMatchObject({backup_verified:false}));
 it("requires consistent completion state",()=>{expect(parseArchiveBatch({...batch(),state:"archived"})).toBeNull();expect(parseArchiveBatch({...batch(),state:"archived",archived_at:"2026-11-26T01:00:00Z"})?.state).toBe("archived");});
 it("validates integer counts and amounts",()=>{const b=batch();b.payments[0].total=99;expect(parseArchiveBatch(b)).toBeNull();expect(parseArchiveBatch({...batch(),counts:{"public.payments":57,other:-1}})).toBeNull();});
 it("sends only the reviewed batch, hash, reason and exact confirmation",()=>expect(buildArchiveArgs(form())).toEqual({p_batch:ID,p_snapshot_sha256:SHA,p_reason:"Owner-approved pre-launch test cleanup",p_confirmation:ARCHIVE_CONFIRMATION}));
 it.each(["confirmation","reason","batch_id","snapshot_sha256"])("refuses missing %s",name=>{const f=form();f.delete(name);expect(buildArchiveArgs(f)).toBeNull();});
 it("requires the exact receipt before reporting success",()=>{const args=buildArchiveArgs(form())!;const r={status:"archived",batch_id:ID,snapshot_sha256:SHA,counts:{"public.payments":57}};expect(isArchiveReceipt(r,args)).toBe(true);for(const patch of [{status:"prepared"},{batch_id:"wrong"},{snapshot_sha256:"wrong"},{counts:{"public.payments":56}},{}]){if(Object.keys(patch).length)expect(isArchiveReceipt({...r,...patch},args)).toBe(false);}expect(isArchiveReceipt(null,args)).toBe(false);});
});
