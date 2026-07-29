export function Skeleton({ className = "" }: { className?: string }) {
  return (
    <div
      aria-hidden="true"
      className={`animate-pulse rounded-[4px] bg-white/[0.05] motion-reduce:animate-none ${className}`}
    />
  );
}

export function ListingCardSkeleton() {
  return (
    <div>
      <Skeleton className="aspect-[4/3] w-full rounded-[6px]" />
      <div className="space-y-2.5 pt-4">
        <Skeleton className="h-3 w-2/5" />
        <Skeleton className="h-4 w-3/4" />
        <div className="flex items-center justify-between pt-2">
          <Skeleton className="h-5 w-20" />
          <Skeleton className="h-3 w-14" />
        </div>
      </div>
    </div>
  );
}
