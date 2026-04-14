/**
 * src/lib/platformInstructions.ts — Platform Instruction Engine
 *
 * Static JSON-driven instruction system that maps ticket_platform to
 * structured step-by-step guides for both seller (sending) and buyer
 * (receiving) transfer flows.
 *
 * Why static JSON instead of database:
 *   - Platform instructions change rarely and are read-heavy
 *   - Ships with the app — works offline, zero query latency
 *   - Update via app release, not migration
 *
 * Adding a new platform:
 *   1. Add the value to TicketPlatform union in src/types/index.ts
 *   2. Add the CHECK constraint value in a migration
 *   3. Add an entry to PLATFORM_INSTRUCTIONS below
 *   4. No code changes needed — components read from the map
 *
 * Phase A — migration 011
 */

import type { TicketPlatform, TransferMethod } from '@/src/types';

// ─── Types ───────────────────────────────────────────────────────────────────

export interface PlatformInstruction {
  platform: TicketPlatform;
  displayName: string;
  icon: string;
  transferMethods: TransferMethod[];
  seller: {
    title: string;
    steps: string[];
    tips: string[];
    estimatedTime: string;
    videoUrl?: string;
  };
  buyer: {
    title: string;
    steps: string[];
    tips: string[];
    estimatedTime: string;
  };
  warnings: string[];
}

// ─── Helper ──────────────────────────────────────────────────────────────────

/**
 * Replace `{buyer_email}` and `{buyer_phone}` placeholders in a step string
 * with actual values. Falls back to a readable placeholder if the value is
 * not yet available.
 */
export function interpolateStep(
  step: string,
  buyerEmail?: string | null,
  buyerPhone?: string | null,
): string {
  return step
    .replace(/\{buyer_email\}/g, buyerEmail || '(email not yet provided)')
    .replace(/\{buyer_phone\}/g, buyerPhone || '(phone not yet provided)');
}

// ─── Instruction Data ────────────────────────────────────────────────────────

export const PLATFORM_INSTRUCTIONS: Record<TicketPlatform, PlatformInstruction> = {
  dice: {
    platform: 'dice',
    displayName: 'DICE',
    icon: '\u{1F3B2}',
    transferMethods: ['mobile_transfer'],
    seller: {
      title: 'How to transfer tickets on DICE',
      steps: [
        'Open the DICE app on your phone',
        'Go to "My Tickets" from the bottom menu',
        'Find and tap on the event',
        'Tap "Transfer Ticket"',
        'Enter the buyer\'s email address: {buyer_email}',
        'Confirm the transfer',
        'Take a screenshot of the confirmation',
      ],
      tips: [
        'Make sure you\'re transferring the correct ticket(s)',
        'The buyer must have a DICE account with the email you send to',
        'Transfers usually arrive within a few minutes',
      ],
      estimatedTime: '2-5 minutes',
    },
    buyer: {
      title: 'How to receive tickets on DICE',
      steps: [
        'Make sure you have the DICE app installed',
        'Check that your DICE account uses the email you provided',
        'You\'ll receive a notification when the seller sends your ticket',
        'Open DICE \u2192 "My Tickets" to see the transferred ticket',
        'If you don\'t see it, check your email for a transfer link',
      ],
      tips: [
        'If you don\'t have a DICE account, create one with the same email you gave the seller',
        'Transfers typically arrive within minutes',
        'Contact us if you haven\'t received the transfer within 2 hours',
      ],
      estimatedTime: '1-2 minutes to accept',
    },
    warnings: [
      'DICE tickets can only be transferred once',
      'Make sure the email address is correct before transferring',
    ],
  },

  eventbrite: {
    platform: 'eventbrite',
    displayName: 'Eventbrite',
    icon: '\u{1F39F}\uFE0F',
    transferMethods: ['email'],
    seller: {
      title: 'How to transfer tickets on Eventbrite',
      steps: [
        'Go to eventbrite.com or open the Eventbrite app',
        'Navigate to "Tickets" or "My Orders"',
        'Find the event and click "Transfer"',
        'Enter the buyer\'s email: {buyer_email}',
        'Add a message (optional)',
        'Click "Transfer"',
        'Screenshot the confirmation page',
      ],
      tips: [
        'Eventbrite sends the buyer a new ticket via email',
        'Your original ticket will be cancelled after transfer',
      ],
      estimatedTime: '3-5 minutes',
    },
    buyer: {
      title: 'How to receive tickets on Eventbrite',
      steps: [
        'Check your email (including spam/promotions) for a transfer notification from Eventbrite',
        'Click "Accept Transfer" in the email',
        'Sign in to or create an Eventbrite account',
        'Your ticket will appear in "My Tickets"',
      ],
      tips: [
        'Check your spam folder if you don\'t see the email',
        'You can also check eventbrite.com \u2192 My Tickets',
      ],
      estimatedTime: '1-2 minutes to accept',
    },
    warnings: [
      'Some Eventbrite events do not allow transfers. The seller should verify before listing.',
    ],
  },

  posh: {
    platform: 'posh',
    displayName: 'Posh',
    icon: '\u2728',
    transferMethods: ['mobile_transfer'],
    seller: {
      title: 'How to transfer tickets on Posh',
      steps: [
        'Open the Posh app',
        'Go to "My Tickets"',
        'Tap on the event',
        'Tap "Send Ticket"',
        'Enter the buyer\'s phone number: {buyer_phone}',
        'Confirm the send',
        'Screenshot the confirmation',
      ],
      tips: [
        'Posh transfers work via phone number, not email',
        'The buyer must have the Posh app installed',
      ],
      estimatedTime: '2-3 minutes',
    },
    buyer: {
      title: 'How to receive tickets on Posh',
      steps: [
        'Install the Posh app if you don\'t have it',
        'Sign up with the phone number you provided',
        'You\'ll see the ticket appear in "My Tickets"',
        'You may also receive a text notification',
      ],
      tips: [
        'Make sure your Posh account is registered with the phone number you gave the seller',
      ],
      estimatedTime: '1 minute to accept',
    },
    warnings: [
      'Posh requires the recipient to have an account with the same phone number',
    ],
  },

  axs: {
    platform: 'axs',
    displayName: 'AXS',
    icon: '\u{1F3AB}',
    transferMethods: ['mobile_transfer', 'email'],
    seller: {
      title: 'How to transfer tickets on AXS',
      steps: [
        'Open the AXS app or go to axs.com',
        'Go to "My Events"',
        'Select the event and tap "Transfer"',
        'Enter the buyer\'s email: {buyer_email}',
        'Confirm the transfer',
        'Screenshot the confirmation',
      ],
      tips: [
        'AXS transfers can be done via app or website',
        'The recipient gets an email to claim the ticket',
      ],
      estimatedTime: '3-5 minutes',
    },
    buyer: {
      title: 'How to receive tickets on AXS',
      steps: [
        'Check your email for a transfer notification from AXS',
        'Click "Accept" in the email',
        'Sign in to or create your AXS account',
        'Ticket appears in "My Events" in the AXS app',
      ],
      tips: [
        'Download the AXS app to access your mobile ticket on event day',
      ],
      estimatedTime: '2-3 minutes',
    },
    warnings: [],
  },

  ticketmaster: {
    platform: 'ticketmaster',
    displayName: 'Ticketmaster',
    icon: '\u{1F3AA}',
    transferMethods: ['mobile_transfer', 'email'],
    seller: {
      title: 'How to transfer tickets on Ticketmaster',
      steps: [
        'Open the Ticketmaster app or go to ticketmaster.com',
        'Go to "My Events"',
        'Tap on the event \u2192 "Transfer"',
        'Enter the buyer\'s name and email: {buyer_email}',
        'Confirm the transfer',
        'Screenshot the confirmation',
      ],
      tips: [
        'Some events restrict transfers \u2014 verify before listing',
        'Ticketmaster transfers are usually instant',
      ],
      estimatedTime: '2-5 minutes',
    },
    buyer: {
      title: 'How to receive tickets on Ticketmaster',
      steps: [
        'Check your email for a transfer from Ticketmaster',
        'Click "Accept Tickets"',
        'Sign in to your Ticketmaster account (create one if needed)',
        'Tickets appear in "My Events"',
      ],
      tips: [
        'Use the same email address you provided to the seller',
        'Download the Ticketmaster app for mobile tickets',
      ],
      estimatedTime: '1-2 minutes',
    },
    warnings: [
      'Some Ticketmaster events have transfer restrictions',
    ],
  },

  other: {
    platform: 'other',
    displayName: 'Other Platform',
    icon: '\u{1F4E7}',
    transferMethods: ['email', 'mobile_transfer'],
    seller: {
      title: 'How to transfer your tickets',
      steps: [
        'Open the app or website where you purchased the tickets',
        'Find the ticket transfer or send option',
        'Enter the buyer\'s contact info as provided',
        'Complete the transfer',
        'Take a screenshot of the confirmation',
      ],
      tips: [
        'If the platform doesn\'t support transfer, contact the event organizer',
      ],
      estimatedTime: '5-10 minutes',
    },
    buyer: {
      title: 'How to receive your tickets',
      steps: [
        'Check your email and phone for a transfer notification',
        'Follow the instructions in the notification to accept',
        'Download any required app for the ticket platform',
      ],
      tips: [
        'Contact the seller via SnatchIt if you haven\'t received anything within 2 hours',
      ],
      estimatedTime: 'Varies',
    },
    warnings: [
      'Transfer process varies by platform. If you have issues, open a dispute.',
    ],
  },
};
