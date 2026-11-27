import {beforeEach,describe,expect,it,vi} from "vitest";
const rpc=vi.hoisted(()=>vi.fn());vi.mock("server-only",()=>({}));vi.mock("@/lib/ops",()=>({callOps:rpc}));
import {getAdminUserEmails,parseAdminUserEmails} from "@/lib/admin-user-emails";
const id="aaaaaaaa-0000-4000-8000-000000000001",other="bbbbbbbb-0000-4000-8000-000000000001";
beforeEach(()=>vi.clearAllMocks());
describe("admin email boundary",()=>{
 it.each(["platform_support","platform_risk"] as const)("never requests full emails for %s",async role=>{expect(await getAdminUserEmails(role,[id])).toEqual({state:"masked"});expect(rpc).not.toHaveBeenCalled();});
 it("looks up only displayed IDs with the existing gated client",async()=>{rpc.mockResolvedValue({ok:true,data:[{id,email:"buyer@example.test"}]});expect(await getAdminUserEmails("platform_admin",[id])).toEqual({state:"ready",emails:{[id]:"buyer@example.test"}});expect(rpc).toHaveBeenCalledExactlyOnceWith("admin_user_emails",{p_user_ids:[id]});});
 it("does not turn failed or malformed lookup into blank contacts",async()=>{for(const result of [{ok:false,kind:"denied"},{ok:true,data:[]},{ok:true,data:[{id:other,email:"other@example.test"}]}]){rpc.mockResolvedValue(result);expect(await getAdminUserEmails("platform_admin",[id])).toEqual({state:"unavailable"});}});
 it.each([null,{},[{id,email:42}],[{id,email:"bad\n@example.test"}],[{id,email:"buyer@example.test"},{id,email:"buyer@example.test"}]])("refuses malformed or duplicate contact data %j",value=>expect(parseAdminUserEmails(value,[id])).toBeNull());
 it("accepts an explicitly absent email without inventing one",()=>expect(parseAdminUserEmails([{id,email:null}],[id])).toEqual({[id]:null}));
 it("does not request all users for an empty page",async()=>{expect(await getAdminUserEmails("platform_admin",[])).toEqual({state:"ready",emails:{}});expect(rpc).not.toHaveBeenCalled();});
});
