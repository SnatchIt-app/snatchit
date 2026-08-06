import { Container } from "@/components/ui/Container";
import { Skeleton } from "@/components/ui/Skeleton";

export default function Loading() {
  return (
    <Container className="max-w-[560px] py-12">
      <Skeleton className="h-8 w-56" />
      <Skeleton className="mt-4 h-4 w-72" />
      <div className="mt-8 space-y-4">
        {Array.from({ length: 5 }).map((_, i) => (
          <Skeleton key={i} className="h-12 w-full" />
        ))}
      </div>
    </Container>
  );
}
