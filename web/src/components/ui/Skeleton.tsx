export function Skeleton({ className = "" }: { className?: string }) {
  return <div aria-hidden="true" className={`skeleton rounded-media ${className}`} />;
}

/** Feed-row placeholder (native FeedRow geometry). */
export function FeedRowSkeleton() {
  return (
    <div className="flex items-center gap-4 py-4">
      <Skeleton className="h-[78px] w-[62px] shrink-0" />
      <div className="min-w-0 flex-1 space-y-2">
        <Skeleton className="h-4 w-3/4" />
        <Skeleton className="h-3 w-1/2" />
      </div>
      <Skeleton className="h-5 w-16" />
    </div>
  );
}

export function ListingCardSkeleton() {
  return (
    <div>
      <Skeleton className="aspect-[4/5] w-full rounded-panel" />
      <div className="mt-3 space-y-2">
        <Skeleton className="h-4 w-3/4" />
        <Skeleton className="h-3 w-1/2" />
        <Skeleton className="h-5 w-20" />
      </div>
    </div>
  );
}
