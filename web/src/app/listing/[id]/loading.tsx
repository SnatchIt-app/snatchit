import { Container } from "@/components/ui/Container";
import { Skeleton } from "@/components/ui/Skeleton";

/** Listing detail placeholder in the page's own geometry: 4:5 poster, identity, purchase panel. */
export default function Loading() {
  return (
    <div className="pb-10">
      <Container className="flex items-center justify-between py-3 lg:py-5">
        <Skeleton className="size-11 rounded-full" />
        <Skeleton className="h-11 w-24 rounded-full" />
      </Container>
      <Container>
        <div role="status" aria-label="Loading listing" className="grid gap-6 lg:grid-cols-[minmax(0,1fr)_420px] lg:gap-x-14">
          <Skeleton className="-mx-5 aspect-[4/5] w-[calc(100%+40px)] rounded-none sm:mx-0 sm:w-full sm:rounded-card lg:max-w-[600px]" />
          <div>
            <Skeleton className="h-6 w-48 rounded-full" />
            <Skeleton className="mt-4 h-4 w-56" />
            <Skeleton className="mt-3 h-10 w-3/4" />
            <Skeleton className="mt-6 h-72 rounded-card" />
          </div>
        </div>
      </Container>
    </div>
  );
}
