import Link from"next/link";
import{PageHeader}from"@/components/ui/PageHeader";
import{Alert,OpsFailureAlert}from"@/components/ui/Alert";
import{ListingArchiveForm}from"@/components/system/ListingArchiveForm";
import{requireOperator}from"@/lib/auth/session";
import{callOps}from"@/lib/ops";
import{CATALOG_LABELS,parseListingArchive}from"@/lib/listing-archive";
export const dynamic="force-dynamic";
export const metadata={title:"Older listing archive"};
export default async function ListingArchivePage(){
 const me=await requireOperator();const header=<PageHeader eyebrow="System"title="Older listing archive"description="The older listings leave active operations, with their bids and recovery copy kept here."back={{href:"/system/prelaunch-archive",label:"Back to test archive"}}/>;
 if(me.role!=="platform_admin")return<>{header}<Alert state="denied"title="Platform admin access required."/></>;
 const r=await callOps<unknown>("prelaunch_listing_read");if(!r.ok)return<>{header}<OpsFailureAlert failure={r}fn="prelaunch_listing_read"subject="Listing archive"retryHref="/system/listing-archive"/></>;
 const b=parseListingArchive(r.data);if(!b)return<>{header}<Alert state="failed"title="The archive preview could not be verified. Cleanup is locked."/></>;
 if(b.state==="not_prepared")return<>{header}<Alert state="info"title="The reviewed backup has not been prepared. No listings have moved."/></>;
 return<>{header}<section className="panel p-5 mb-6"><h2 className="title-section">Five listings stay</h2><p className="mt-3">DD, ANOTR, James Hype + HILLS, Adiel &amp; Yu Su, and IDEMI: Halloween Night. Daniel’s purchase and the latest rehearsal payment stay unchanged. No accounts, money or ticket ownership are removed.</p><dl className="mt-4 grid gap-2 sm:grid-cols-2">{Object.entries(b.counts).map(([key,count])=><div key={key}><dt className="text-muted">{CATALOG_LABELS[key as keyof typeof CATALOG_LABELS]}</dt><dd>{count}</dd></div>)}</dl>
 {b.state==="archived"?<Alert state="success"title="The 113 older listings are archived. This cleanup cannot run twice."/>:b.ready?<ListingArchiveForm digest={b.digest}/>:<Alert state="info"title="Cleanup stays locked until the recovery copy is verified."/>}</section>
 <section className="panel p-5"><h2 className="title-section">Listing history</h2><p className="mt-2">Old reports still open the archived listing. Recovery copies and images are retained.</p><ul className="mt-4 space-y-2">{b.listings.map(l=><li key={l.id}><Link className="underline"href={`/marketplace/${l.id}`}>{l.event_name}</Link></li>)}</ul></section></>;
}
