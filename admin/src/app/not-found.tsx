import Link from "next/link";

export default function NotFound() {
  return (
    <main className="flex min-h-dvh items-center justify-center p-8">
      <div className="border border-line bg-card p-6 text-center">
        <p className="eyebrow text-primary">404</p>
        <h1 className="mt-1 text-xl font-bold">Not found</h1>
        <p className="mt-4">
          <Link href="/" className="link">
            Back to Today
          </Link>
        </p>
      </div>
    </main>
  );
}
