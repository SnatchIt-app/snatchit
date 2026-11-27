import {beforeEach,describe,expect,it,vi} from "vitest";
const m=vi.hoisted(()=>({operator:vi.fn(),rpc:vi.fn(),refresh:vi.fn()}));
vi.mock("server-only",()=>({}));vi.mock("@/lib/auth/session",()=>({requireOperator:m.operator}));vi.mock("@/lib/ops",()=>({callOps:m.rpc}));vi.mock("next/cache",()=>({revalidatePath:m.refresh}));
import {archivePrelaunchTests} from "@/lib/prelaunch-archive-actions";
const id="aaaaaaaa-0000-4000-8000-000000000001",sha="a".repeat(64);
const form=()=>{const f=new FormData();for(const [k,v]of Object.entries({batch_id:id,snapshot_sha256:sha,reason:"Owner-approved pre-launch test cleanup",confirmation:"ARCHIVE 57 TEST ORDERS"}))f.set(k,v);return f;};
beforeEach(()=>{vi.clearAllMocks();m.operator.mockResolvedValue({role:"platform_admin"});});
describe("archive server action",()=>{
 it("refuses a support operator before any RPC",async()=>{m.operator.mockResolvedValue({role:"platform_support"});expect(await archivePrelaunchTests({},form())).toHaveProperty("error");expect(m.rpc).not.toHaveBeenCalled();});
 it("refuses malformed confirmation before any RPC",async()=>{const f=form();f.set("confirmation","yes");expect(await archivePrelaunchTests({},f)).toHaveProperty("error");expect(m.rpc).not.toHaveBeenCalled();});
 it("does not claim success after a lost/refused response",async()=>{m.rpc.mockResolvedValue({ok:false,kind:"error"});expect(await archivePrelaunchTests({},form())).toHaveProperty("error");expect(m.refresh).not.toHaveBeenCalled();});
 it("explains a stale backup without suggesting a refresh-only retry",async()=>{m.rpc.mockResolvedValue({ok:false,kind:"error",code:"P0001",message:"archive_refused: source changed since backup"});const state=await archivePrelaunchTests({},form());expect(state.error).toContain("fresh review and verified backup");expect(state.error).toContain("refreshing this page alone will not fix it");expect(state.completed).toBeUndefined();expect(m.refresh).not.toHaveBeenCalled();});
 it.each(["mfa","denied"])("gives sign-in guidance for %s",async(kind)=>{m.rpc.mockResolvedValue({ok:false,kind});expect((await archivePrelaunchTests({},form())).error).toContain("sign-in");expect(m.refresh).not.toHaveBeenCalled();});
 it("does not expose an unknown server error or assume failure means no commit",async()=>{m.rpc.mockResolvedValue({ok:false,kind:"error",code:"P0001",message:"private sentinel"});const state=await archivePrelaunchTests({},form());expect(state.error).not.toContain("private sentinel");expect(state.error).toContain("no success is assumed");});
 it("refuses an unrelated or incomplete receipt",async()=>{m.rpc.mockResolvedValue({ok:true,data:{status:"archived"}});expect(await archivePrelaunchTests({},form())).toHaveProperty("error");expect(m.refresh).not.toHaveBeenCalled();});
 it("uses the gated RPC with exact identities and refreshes live sections only on the exact receipt",async()=>{m.rpc.mockResolvedValue({ok:true,data:{status:"archived",batch_id:id,snapshot_sha256:sha,counts:{"public.payments":57}}});expect(await archivePrelaunchTests({},form())).toEqual({completed:true});expect(m.rpc).toHaveBeenCalledExactlyOnceWith("prelaunch_archive_execute",{p_batch:id,p_snapshot_sha256:sha,p_reason:"Owner-approved pre-launch test cleanup",p_confirmation:"ARCHIVE 57 TEST ORDERS"});expect(m.refresh).toHaveBeenCalledWith("/orders");expect(m.refresh).toHaveBeenCalledWith("/money");});
});
