import{beforeEach,describe,expect,it,vi}from"vitest";
const rpc=vi.hoisted(()=>vi.fn());
const operator=vi.hoisted(()=>vi.fn());
vi.mock("@/lib/ops",()=>({callOps:rpc}));vi.mock("@/lib/auth/session",()=>({requireOperator:operator}));vi.mock("next/cache",()=>({revalidatePath:vi.fn()}));
import{archiveOldListings,checkListingArchiveConnection}from"@/lib/listing-archive-actions";
import{LISTING_ARCHIVE_CONFIRMATION,KEPT_LISTINGS,parseListingArchive,listingArchiveArgs,listingArchiveReceipt}from"@/lib/listing-archive";
const digest="a".repeat(64);
const preview=()=>({state:"prepared",digest,ready:true,archived_at:null,counts:{"public.listings":113,"public.bids":98,"public.listing_visibility":113,"public.saved_listings":1},listings:Array.from({length:113},(_,i)=>({id:`21900000-0000-4000-8000-${i.toString().padStart(12,"0")}`,event_name:"Old fixture"}))});
const receipt=()=>({status:"archived",digest,listings:113,kept:5});
function form(){const f=new FormData();f.set("digest",digest);f.set("reason","Owner approved one-time listing cleanup");f.set("confirmation",LISTING_ARCHIVE_CONFIRMATION);return f;}
beforeEach(()=>{vi.clearAllMocks();operator.mockResolvedValue({role:"platform_admin"});});
describe("listing archive boundary",()=>{
 it("accepts exact bounded preview",()=>expect(parseListingArchive(preview())).toMatchObject({state:"prepared",ready:true}));
 it.each([null,{},[],{state:"archived"}])("rejects malformed preview %j",v=>expect(parseListingArchive(v)).toBeNull());
 it("rejects protected, duplicate and incomplete IDs",()=>{for(const mutate of[(b:ReturnType<typeof preview>)=>b.listings.splice(0,1),(b:ReturnType<typeof preview>)=>b.listings[0]=b.listings[1],(b:ReturnType<typeof preview>)=>b.listings[0].id=KEPT_LISTINGS[0]]){const b=preview();mutate(b);expect(parseListingArchive(b)).toBeNull();}});
 it("rejects incomplete or expanded scope",()=>{const b=preview();expect(parseListingArchive({...b,counts:{...b.counts,"public.payments":1}})).toBeNull();expect(parseListingArchive({...b,counts:{"public.listings":113}})).toBeNull();});
 it("requires consistent completion date",()=>{expect(parseListingArchive({...preview(),state:"archived"})).toBeNull();expect(parseListingArchive({...preview(),state:"archived",archived_at:"2026-11-27T21:00:00Z"})?.state).toBe("archived");});
 it("does not treat truthy text as backup approval",()=>expect(parseListingArchive({...preview(),ready:"true"})).toMatchObject({ready:false}));
 it.each(["digest","reason","confirmation"])("requires %s",key=>{const f=form();f.delete(key);expect(listingArchiveArgs(f)).toBeNull();});
 it("validates exact receipt",()=>{expect(listingArchiveReceipt(receipt(),digest)).toBe(true);for(const patch of[{digest:"b".repeat(64)},{listings:112},{kept:4},{status:"prepared"}])expect(listingArchiveReceipt({...receipt(),...patch},digest)).toBe(false);});
 it("connection check cannot submit a valid digest",async()=>{rpc.mockResolvedValue({ok:false,kind:"error",code:"P0001",message:"catalog_archive_refused: verified backup required"});expect(await checkListingArchiveConnection()).toEqual({checked:true});expect(rpc).toHaveBeenCalledExactlyOnceWith("prelaunch_listing_execute",expect.objectContaining({p_digest:""}));});
 it("connection check never calls the service for support",async()=>{operator.mockResolvedValue({role:"platform_support"});expect(await checkListingArchiveConnection()).toHaveProperty("error");expect(rpc).not.toHaveBeenCalled();});
 it("shows MFA and cardinality failures honestly",async()=>{for(const response of[{ok:false,kind:"mfa"},{ok:false,kind:"error",code:"21000",message:"more than one row"}]){rpc.mockResolvedValue(response);const r=await archiveOldListings({},form());expect(r.error).toContain(response.kind==="mfa"?"verification expired":"21000");expect(r.completed).toBeUndefined();}});
 it("does not call cleanup for a non-admin",async()=>{operator.mockResolvedValue({role:"platform_support"});expect(await archiveOldListings({},form())).toHaveProperty("error");expect(rpc).not.toHaveBeenCalled();});
 it("uses the existing own-session RPC and exact confirmation",async()=>{rpc.mockResolvedValue({ok:true,data:receipt()});expect(await archiveOldListings({},form())).toEqual({completed:true});expect(rpc).toHaveBeenCalledExactlyOnceWith("prelaunch_listing_execute",listingArchiveArgs(form()));});
 it("never claims success after failure or a wrong receipt",async()=>{for(const response of[{ok:false,kind:"error"},{ok:true,data:{...receipt(),kept:4}}]){rpc.mockResolvedValue(response);expect(await archiveOldListings({},form())).toHaveProperty("error");}});
});
