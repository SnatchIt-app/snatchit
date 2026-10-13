import Image from "next/image";
import { coverImageUrl } from "@/lib/format";

/**
 * Event art at the native 4:5 poster slot (src/lib/media/slots.ts): fitted
 * whole — flyers carry the line-up and the date, so they are never cropped —
 * on the letterbox colour, with no overlay text and no scrim.
 */
export function Poster({
  path,
  alt,
  sizes,
  priority = false,
  rounded = "rounded-panel",
  className = "",
}: {
  path: string;
  alt: string;
  sizes: string;
  priority?: boolean;
  rounded?: string;
  className?: string;
}) {
  return (
    <div className={`poster relative aspect-[4/5] overflow-hidden ${rounded} ${className.includes("w-") ? "" : "w-full"} ${className}`}>
      <Image src={coverImageUrl(path)} alt={alt} fill priority={priority} sizes={sizes} className="object-contain" />
    </div>
  );
}
