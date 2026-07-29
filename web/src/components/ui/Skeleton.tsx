export function Skeleton({ className = "" }: { className?: string }) {
  return (
    <div
      aria-hidden="true"
      className={`animate-pulse bg-white/[0.05] motion-reduce:animate-none ${className}`}
    />
  );
}

export function ListingCardSkeleton() {
  return (
    <div className="overflow-hidden border border-primary/15 bg-card">
      <Skeleton className="aspect-[4/3] w-full" />
      <div className="space-y-2.5 p-4">
        <Skeleton className="h-3 w-2/5" />
        <Skeleton className="h-5 w-3/4" />
        <Skeleton className="h-3 w-1/2" />
        <div className="flex items-center justify-between border-t border-primary/10 pt-3">
          <Skeleton className="h-5 w-20" />
          <Skeleton className="h-3 w-16" />
        </div>
      </div>
    </div>
  );
}
