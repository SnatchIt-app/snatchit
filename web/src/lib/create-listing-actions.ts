"use server";

import { getAuthedUser } from "@/lib/auth/session";
import {
  createListing,
  getListingGates,
  uploadListingImage,
  type CreateListingPayload,
  type ImageKind,
  type ListingGates,
} from "@/lib/create-listing";

export async function getListingGatesAction(): Promise<ListingGates | { error: string }> {
  const user = await getAuthedUser();
  if (!user) return { error: "AUTH_REQUIRED" };
  return getListingGates(user.id);
}

export async function uploadListingImageAction(
  kind: ImageKind,
  file: File,
): Promise<{ path?: string; error?: string }> {
  const user = await getAuthedUser();
  if (!user) return { error: "AUTH_REQUIRED" };
  return uploadListingImage(user.id, kind, file);
}

export async function createListingAction(
  payload: CreateListingPayload,
): Promise<{ id?: string; error?: string }> {
  const user = await getAuthedUser();
  if (!user) return { error: "AUTH_REQUIRED" };
  return createListing(user.id, payload);
}
