import { Container } from "@/components/ui/Container";
import { Skeleton } from "@/components/ui/Skeleton";

export default function Loading() {
  return (
    <Container size="narrow" className="pb-12 pt-3 lg:pt-6">
      <div role="status" aria-label="Loading transfer">
        <Skeleton className="size-11 rounded-full" />
        <div className="mt-6 flex gap-4">
          <Skeleton className="h-[78px] w-[62px]" />
          <div className="flex-1 space-y-2">
            <Skeleton className="h-5 w-28" />
            <Skeleton className="h-6 w-3/4" />
            <Skeleton className="h-4 w-1/2" />
          </div>
        </div>
        <div className="mt-7 space-y-4">
          <Skeleton className="h-16 rounded-panel" />
          <Skeleton className="h-48 rounded-panel" />
        </div>
      </div>
    </Container>
  );
}
