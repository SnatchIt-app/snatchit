import {renderToStaticMarkup} from "react-dom/server";
import {beforeEach,describe,expect,it,vi} from "vitest";
const m=vi.hoisted(()=>({rpc:vi.fn(),operator:vi.fn()}));
vi.mock("server-only",()=>({}));vi.mock("@/lib/ops",()=>({callOps:m.rpc}));vi.mock("@/lib/auth/session",()=>({requireOperator:m.operator}));
vi.mock("next/navigation",()=>({notFound:()=>{throw Error("notFound");},redirect:()=>{throw Error("redirect");},usePathname:()=>"/orders",useRouter:()=>({push(){},replace(){},refresh(){}}),useParams:()=>({})}));
import OrderPage from "@/app/(console)/orders/[paymentId]/page";
const id="d44d0d3d-90e0-4e3b-a6bd-2769275ec741";
beforeEach(()=>{vi.clearAllMocks();m.operator.mockResolvedValue({id:"2b117757-f4e3-41c1-b7df-68a4502d0fba",role:"platform_admin"});});
async function render(mode:string){m.rpc.mockImplementation(async(fn:string)=>{if(fn==="order_detail")return {ok:true,data:{payment:{id,status:"succeeded",amount:100,buyer_fee:10,seller_fee:0,total:110,mode,stripe_livemode:true},transfer:null,listing:null,buyer:null,seller:null,disputes:[],dispute_resolutions:[],payout_decisions:[],refund:{payment_status:"succeeded",refund_actions:[]},seller_funds_state:"not_applicable",cases:[],actions:[],evidence:{},bank_payout:{tracked:false,note:null}}};if(fn==="order_timeline")return {ok:true,data:{events:[]}};if(fn==="settings")return {ok:true,data:[{key:"refund_execute_enabled",value:false}]};if(fn==="list_actions")return {ok:true,data:{items:[],next_cursor:null}};return {ok:false,kind:"error"};});return renderToStaticMarkup(await OrderPage({params:Promise.resolve({paymentId:id})}));}
describe("actual order page distinguishes native issuance from resale settlement",()=>{
 it("does not call a missing resale transfer a native settlement failure",async()=>{const h=await render("native_primary");expect(h).toContain("Native ticket purchases do not use a resale transfer.");expect(h).toContain("native-order reconciliation");expect(h).not.toContain("This is a settlement gap.");});
 it("keeps the resale settlement warning",async()=>{const h=await render("buy_now");expect(h).toContain("This is a settlement gap.");expect(h).not.toContain("Native ticket purchases do not use a resale transfer.");});
});
