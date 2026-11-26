import { PageHeader } from "@/components/ui/PageHeader";
import { Alert, OpsFailureAlert } from "@/components/ui/Alert";
import { Money } from "@/components/ui/Money";
import { PrelaunchArchiveForm } from "@/components/system/PrelaunchArchiveForm";
import { requireOperator } from "@/lib/auth/session";
import { callOps } from "@/lib/ops";
import { parseArchiveBatch } from "@/lib/prelaunch-archive";

export const dynamic = "force-dynamic";
export const metadata = { title: "Pre-launch test archive" };
export default async function PrelaunchArchivePage() {
  const me = await requireOperator();
  const header = <PageHeader eyebrow="System" title="Pre-launch test archive" description="A separate home for the old tests, with a full recovery copy. Active orders and business totals use the live records." back={{ href: "/system", label: "Back to platform health" }} />;
  if (me.role !== "platform_admin") return <>{header}<Alert state="denied" title="Platform admin access required." /></>;
  const result = await callOps<unknown>("prelaunch_archive_read");
  if (!result.ok) return <>{header}<OpsFailureAlert failure={result} fn="prelaunch_archive_read" subject="Test archive" retryHref="/system/prelaunch-archive" /></>;
  const batch = parseArchiveBatch(result.data);
  if (!batch) return <>{header}<Alert state="failed" title="The archive response could not be verified. No cleanup is available." /></>;
  if (batch.state === "not_prepared") return <>{header}<Alert state="info" title="No cleanup batch has been prepared.">No records have been moved. The reviewed order list and verified backup must be prepared first.</Alert></>;
  return <>{header}
    <section className="panel p-5 mb-6" aria-labelledby="archive-scope"><h2 id="archive-scope" className="title-section">{batch.state === "archived" ? "Archived test records" : "Review this one-time cleanup"}</h2>
      <p className="mt-3">57 old test orders. Daniel’s $2.20 purchase and the latest $1.10 rehearsal stay active, including their linked records. The unpaid $1.80 seller balance stays visible.</p>
      <p className="mt-3">This moves the reviewed records out of active operations. It does not refund a purchase, transfer funds, change a sale’s status, remove an account or open ticket sales.</p>
      <dl className="mt-4 grid gap-2 sm:grid-cols-2">{Object.entries(batch.counts).map(([relation, count]) => <div key={relation}><dt className="text-muted">{relation === "public.payments" ? "Orders" : relation === "public.transfers" ? "Ticket transfers" : relation === "ops.case" ? "Cases" : relation === "public.webhook_retries" ? "Old payment-update retries" : relation.replace(/^(public|ops)\./, "").replaceAll("_", " ")}</dt><dd className="font-medium">{count}</dd></div>)}</dl>
      {batch.state === "prepared" ? batch.execution_ready ? <PrelaunchArchiveForm batchId={batch.id} digest={batch.snapshot_sha256} /> : <Alert state="info" title="Cleanup is locked until the backup and review window are verified." /> : <Alert state="success" title="This batch is archived. The cleanup cannot run a second time." />}
    </section>
    <section className="panel p-5 overflow-x-auto" aria-labelledby="archive-orders"><h2 id="archive-orders" className="title-section">{batch.state === "archived" ? "Order history" : "Orders in the reviewed batch"}</h2><table className="mt-4 w-full text-sm"><caption className="sr-only">Exact 57 reviewed pre-launch test orders</caption><thead><tr><th scope="col" className="text-left p-2">Order reference</th><th scope="col" className="text-left p-2">Created</th><th scope="col" className="text-left p-2">Recorded status</th><th scope="col" className="text-left p-2">Test total</th></tr></thead><tbody>{batch.payments.map(p => <tr key={p.id}><th scope="row" className="text-left p-2 font-mono text-xs">{p.id}</th><td className="p-2">{p.created_at.slice(0, 10)}</td><td className="p-2">{p.status}</td><td className="p-2"><Money cents={p.total} /></td></tr>)}</tbody></table></section>
  </>;
}
