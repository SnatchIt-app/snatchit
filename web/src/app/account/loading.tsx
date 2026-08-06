import { Skeleton } from "@/components/ui/Skeleton";

/**
 * Covers every /account/* child route — they all render inside the account
 * layout and each one awaits at least one query.
 */
export default function AccountLoading() {
  return (
    <div>
      <Skeleton className="h-10 w-64" />
      <div className="mt-6 border-y border-primary/15 py-5">
        <Skeleton className="h-4 w-48" />
      </div>
      <div className="mt-9 space-y-4">
        {Array.from({ length: 4 }).map((_, i) => (
          <Skeleton key={i} className="h-24 w-full" />
        ))}
      </div>
    </div>
  );
}
