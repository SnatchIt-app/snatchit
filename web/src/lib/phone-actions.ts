"use server";

import { getAuthedUser } from "@/lib/auth/session";
import { sendPhoneOtp, verifyPhoneOtp, type PhoneOtpResult } from "@/lib/phone";

export async function sendPhoneOtpAction(rawPhone: string): Promise<PhoneOtpResult> {
  const user = await getAuthedUser();
  if (!user) return { error: "AUTH_REQUIRED" };
  return sendPhoneOtp(rawPhone);
}

export async function verifyPhoneOtpAction(rawPhone: string, code: string): Promise<PhoneOtpResult> {
  const user = await getAuthedUser();
  if (!user) return { error: "AUTH_REQUIRED" };
  return verifyPhoneOtp(rawPhone, code);
}
