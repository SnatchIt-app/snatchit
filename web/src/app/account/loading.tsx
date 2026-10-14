import { FeedRowSkeleton, Skeleton } from "@/components/ui/Skeleton";

/**
 * Covers every /account/* child route — they all render inside the account
 * layout and each one awaits at least one query.
 */
export default function AccountLoading() {
  return (
    <div>
      <Skeleton className="mb-3 size-11 rounded-full lg:hidden" />
      <Skeleton className="h-9 w-56 lg:h-11 lg:w-72" />
      <div className="mt-6 border-t border-line lg:mt-8">
        {Array.from({ length: 4 }).map((_, i) => (
          <div key={i} className="border-b border-line">
            <FeedRowSkeleton />
          </div>
        ))}
      </div>
    </div>
  );
}
