/**
 * src/lib/platformInstructions.ts — Platform Instruction Engine
 *
 * Static JSON-driven instruction system that maps ticket_platform to
 * structured step-by-step guides for both seller (sending) and buyer
 * (receiving) transfer flows.
 *
 * ALL instruction content is grounded in official platform documentation —
 * see TRANSFER_METHOD_RESEARCH.md (repo root) for the source URL behind
 * every claim. Claims that could not be confirmed from an official source
 * were NOT included (App Review safety: no unsupported transfer claims,
 * no screenshots-as-ticket claims unless the platform officially allows it).
 *
 * v2 (migration 033):
 *   - Corrected DICE: transfer is app-only via PHONE CONTACTS, not email.
 *   - Corrected Eventbrite: there is NO account-to-account transfer; the
 *     official mechanism is editing the order's attendee name + email.
 *   - Added 10 platforms: seatgeek, tixr, fever, shotgun, universe,
 *     see_tickets, mlb_ballpark, stubhub, vivid_seats, gametime.
 *
 * Adding a new platform:
 *   1. Add the value to TicketPlatform union in src/types/index.ts
 *   2. Add the CHECK constraint value in a migration
 *   3. Add an entry to PLATFORM_INSTRUCTIONS below (official sources only)
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
  // ───────────────────────────── DICE ────────────────────────────────────────
  // Official: transfers are app-only, recipient picked from PHONE CONTACTS.
  // DICE accounts are phone-number based. No email/link transfer exists.
  dice: {
    platform: 'dice',
    displayName: 'DICE',
    icon: '\u{1F3B2}',
    transferMethods: ['mobile_transfer'],
    seller: {
      title: 'How to send tickets on DICE',
      steps: [
        'Save the buyer\'s phone number to your phone contacts: {buyer_phone}',
        'Open the DICE app and tap the ticket icon',
        'Select the event',
        'Tap "Send ticket to a friend"',
        'Pick the buyer from your contacts and choose how many tickets',
        'Tap Send, then screenshot the confirmation for your records',
      ],
      tips: [
        'DICE transfers work by phone contact — the buyer\'s DICE account must be registered to the phone number you have saved',
        'Transfers must happen before the deadline shown on the ticket (usually a few hours before the event)',
      ],
      estimatedTime: '2-5 minutes',
    },
    buyer: {
      title: 'How to receive tickets on DICE',
      steps: [
        'Install the DICE app and sign up with the phone number you provided to the seller',
        'Wait for the seller to send the ticket from their app',
        'The ticket appears in your DICE app automatically',
      ],
      tips: [
        'Your DICE account phone number must exactly match the number you gave the seller',
        'Contact us through the app if nothing arrives within 2 hours',
      ],
      estimatedTime: '1-2 minutes',
    },
    warnings: [
      'DICE QR codes only activate on the day of the event — "ticket not visible yet" before then is normal',
      'Per DICE: do not rely on screenshots — a screenshotted QR may not be valid for entry',
      'The event organizer can disable transfers, and transfers are impossible after the QR activates',
    ],
  },

  // ─────────────────────────── Eventbrite ────────────────────────────────────
  // Official: NO account-to-account transfer. The purchaser edits the order's
  // attendee name + email; the new attendee claims the ticket.
  eventbrite: {
    platform: 'eventbrite',
    displayName: 'Eventbrite',
    icon: '\u{1F39F}️',
    transferMethods: ['email'],
    seller: {
      title: 'How to pass on Eventbrite tickets (order edit)',
      steps: [
        'Log in to Eventbrite (web or app) with the account that bought the tickets',
        'Go to "Tickets" and select the order',
        'Tap "Edit" on the order information',
        'Change the attendee name to the buyer\'s name and the email to: {buyer_email}',
        'Save — Eventbrite emails the buyer a prompt to claim the ticket',
        'Screenshot the updated order for your records',
      ],
      tips: [
        'Eventbrite has no account-to-account "transfer" — updating the attendee name + email on the order is the official method',
        'Only the original purchaser can edit the order',
      ],
      estimatedTime: '3-5 minutes',
    },
    buyer: {
      title: 'How to receive Eventbrite tickets',
      steps: [
        'Watch your email (including spam) for an Eventbrite "claim tickets" message',
        'Follow the link and sign in / create an Eventbrite account with that email',
        'Your ticket (with QR code) is now under your name in "Tickets"',
      ],
      tips: [
        'Eventbrite tickets are static QR codes — the printed PDF or the app both scan at the door',
        'Some venues check that the attendee name matches your ID',
      ],
      estimatedTime: '1-2 minutes',
    },
    warnings: [
      'If the order has no "Edit" option, the organizer disabled attendee changes — the ticket may not be re-assignable',
    ],
  },

  // ────────────────────────────── Posh ───────────────────────────────────────
  posh: {
    platform: 'posh',
    displayName: 'Posh',
    icon: '✨',
    transferMethods: ['mobile_transfer'],
    seller: {
      title: 'How to transfer tickets on Posh',
      steps: [
        'Open the Posh app and go to your order',
        'Tap "Transfer Tickets"',
        'Select the ticket(s) to send',
        'Enter the buyer\'s phone number: {buyer_phone}',
        'Review and confirm — the transfer shows as pending until accepted',
        'Screenshot the confirmation',
      ],
      tips: [
        'Posh accounts are phone-number based — transfers go to a phone number, not an email',
        'You can cancel a pending transfer until the buyer accepts',
      ],
      estimatedTime: '2-3 minutes',
    },
    buyer: {
      title: 'How to receive tickets on Posh',
      steps: [
        'Install the Posh app and sign up with the phone number you provided',
        'You\'ll get a text/app notification about the transfer',
        'Open it, answer any required checkout questions, and accept',
        'A new order with your ticket appears in your account',
      ],
      tips: [
        'Having your Posh account ready before the seller sends makes acceptance instant',
      ],
      estimatedTime: '1-2 minutes',
    },
    warnings: [
      'Per Posh: payment-plan, comp (free), and approval-required tickets are NOT transferable',
      'After a transfer the original QR scans as "Canceled" — old screenshots are worthless',
      'Organizers can disable transfers per ticket type',
    ],
  },

  // ────────────────────────────── AXS ────────────────────────────────────────
  axs: {
    platform: 'axs',
    displayName: 'AXS',
    icon: '\u{1F3AB}',
    transferMethods: ['mobile_transfer', 'email'],
    seller: {
      title: 'How to transfer tickets on AXS',
      steps: [
        'Open the AXS app (or axs.com) and tap the ticket icon',
        'Select the event and tap "Transfer"',
        'Select the ticket(s)',
        'Enter the buyer\'s first name, last name, and email: {buyer_email}',
        'Verify with the one-time passcode AXS sends you',
        'Review and tap "Transfer Tickets", then screenshot the confirmation',
      ],
      tips: [
        'AXS also accepts a phone number instead of email for the recipient',
        'AXS Mobile ID tickets use "Transfer"; some e-tickets use "Share" (emailed PDF) instead',
      ],
      estimatedTime: '3-5 minutes',
    },
    buyer: {
      title: 'How to receive tickets on AXS',
      steps: [
        'Open the AXS email or text link',
        'Sign in or create an AXS account and download the AXS app',
        'The tickets appear in your AXS account',
      ],
      tips: [
        'Use the same email/phone you gave the seller',
        'Present tickets in the AXS app on event day',
      ],
      estimatedTime: '2-3 minutes',
    },
    warnings: [
      'Transfer availability is event-dependent — some events disable it',
      'VIP add-ons, merch, and insurance typically do not transfer',
    ],
  },

  // ─────────────────────────── Ticketmaster ──────────────────────────────────
  // Covers Live Nation events and Ticketmaster-powered team accounts
  // (Miami Heat / Kaseya Center, Dolphins / Hard Rock Stadium, Inter Miami,
  // Hard Rock Live) — same transfer flow via account manager / team app.
  ticketmaster: {
    platform: 'ticketmaster',
    displayName: 'Ticketmaster / Live Nation',
    icon: '\u{1F3AA}',
    transferMethods: ['mobile_transfer', 'email'],
    seller: {
      title: 'How to transfer tickets on Ticketmaster',
      steps: [
        'Sign in to the Ticketmaster app, ticketmaster.com, or your team account (e.g. Heat, Dolphins, Inter Miami app)',
        'Open "My Tickets" / "My Events" and select the order',
        'Tap "Transfer" (if there is no Transfer button, the event doesn\'t allow it)',
        'Verify with the one-time text code',
        'Select the ticket(s), tap "Transfer To" and enter the buyer\'s email: {buyer_email}',
        'Confirm and screenshot the confirmation',
      ],
      tips: [
        'Transfer by text/phone number is also supported from the app or mobile browser',
        'Live Nation event tickets live in your Ticketmaster account — same flow',
        'Sports tickets (Heat, Dolphins, Inter Miami) transfer the same way via the team app or am.ticketmaster.com',
      ],
      estimatedTime: '2-5 minutes',
    },
    buyer: {
      title: 'How to receive tickets on Ticketmaster',
      steps: [
        'Open the "Accept Tickets" link in the email or text',
        'Sign in or create a Ticketmaster account using the same email the tickets were sent to',
        'The tickets appear in "My Tickets" with a NEW barcode (the seller\'s copy is invalidated)',
      ],
      tips: [
        'Add tickets to Apple/Google Wallet for entry — useful if signal is bad at the venue',
        'The seller can cancel the transfer any time before you accept, so accept promptly',
      ],
      estimatedTime: '1-2 minutes',
    },
    warnings: [
      'SafeTix barcodes refresh every ~15 seconds — per Ticketmaster, screenshots won\'t get you in',
      'Events and artists can disable transfer; merch/VIP packages/insurance do not transfer',
    ],
  },

  // ───────────────────────────── SeatGeek ────────────────────────────────────
  // Miami note: official platform of the Florida Panthers / Amerant Bank Arena.
  seatgeek: {
    platform: 'seatgeek',
    displayName: 'SeatGeek',
    icon: '\u{1F4CD}',
    transferMethods: ['mobile_transfer', 'email'],
    seller: {
      title: 'How to send tickets on SeatGeek',
      steps: [
        'Open the SeatGeek app and go to "Tickets"',
        'Select the event and tap "Transfer"',
        'Select the ticket(s) (and any parking passes)',
        'Enter the buyer\'s email: {buyer_email} (name, username, or phone also work)',
        'Tap "Transfer now" and screenshot the confirmation',
      ],
      tips: [
        'Your SeatGeek email and phone must be verified before you can transfer',
        'Panthers / Amerant Bank Arena tickets are SeatGeek — same flow via the team account manager',
        'You can cancel a pending transfer any time before it\'s accepted — not after',
      ],
      estimatedTime: '2-4 minutes',
    },
    buyer: {
      title: 'How to receive tickets on SeatGeek',
      steps: [
        'Open the email, text, or push notification about the pending transfer',
        'Sign in or create a SeatGeek account with the same email',
        'Go to "Tickets" and accept the transfer',
      ],
      tips: [
        'Tickets for rotating-barcode events must be shown live in the SeatGeek app',
      ],
      estimatedTime: '1-2 minutes',
    },
    warnings: [
      'Per SeatGeek, screenshots are not valid for rotating-barcode tickets (e.g. NFL/NHL events)',
      'Tickets delivered to you via Ticketmaster/AXS/team apps must be re-transferred on THAT platform, not SeatGeek',
    ],
  },

  // ─────────────────────────────── Tixr ──────────────────────────────────────
  // Miami note: LIV, Story, E11EVEN, Daer, M2, Oasis Wynwood run on Tixr.
  tixr: {
    platform: 'tixr',
    displayName: 'Tixr',
    icon: '\u{1F506}',
    transferMethods: ['email'],
    seller: {
      title: 'How to transfer tickets on Tixr',
      steps: [
        'Log in at Tixr.com or in the Tixr app',
        'Open your Wallet and select the event card',
        'Tap "Transfer" (no button = the organizer doesn\'t allow transfers for this event)',
        'Select the ticket(s)',
        'Enter the buyer\'s email: {buyer_email}',
        'Complete the transfer and screenshot the confirmation',
      ],
      tips: [
        'Most Miami mega-clubs (LIV, Story, E11EVEN, Daer, M2, Oasis) ticket through Tixr',
        'Payment-plan tickets must be fully paid before they can transfer',
        'You can cancel the transfer while it is still pending',
      ],
      estimatedTime: '2-4 minutes',
    },
    buyer: {
      title: 'How to receive tickets on Tixr',
      steps: [
        'Open the "Ticket Transfer" email',
        'Tap Accept and log in (or create a Tixr account) with the SAME email the transfer was sent to',
        'Accept the transfer — the tickets move into your Tixr account',
      ],
      tips: [
        'The account email must match the transfer email exactly',
      ],
      estimatedTime: '1-2 minutes',
    },
    warnings: [
      'Tixr contactless (NFC) and rotating-QR tickets can only be used through Tixr — they cannot be exported, and screenshots of rotating codes won\'t scan',
    ],
  },

  // ─────────────────────────────── Fever ─────────────────────────────────────
  fever: {
    platform: 'fever',
    displayName: 'Fever',
    icon: '\u{1F525}',
    transferMethods: ['mobile_transfer'],
    seller: {
      title: 'How to transfer tickets on Fever',
      steps: [
        'Open the Fever app and go to "Tickets"',
        'Select the ticket(s) and tap "Transfer tickets"',
        'Choose "Transfer via link" and select how many tickets',
        'Tap Transfer and share the link with the buyer through Snatch It chat',
        'Screenshot the confirmation',
      ],
      tips: [
        'If there is no Transfer option, that Fever experience doesn\'t allow transfers — check before listing',
      ],
      estimatedTime: '2-3 minutes',
    },
    buyer: {
      title: 'How to receive tickets on Fever',
      steps: [
        'Open the transfer link the seller shares',
        'Download the Fever app and log in / sign up',
        'The tickets appear in your "Tickets" section — you are now the owner',
      ],
      tips: [
        'Accept promptly — transfers only work before the experience starts',
      ],
      estimatedTime: '1-2 minutes',
    },
    warnings: [
      'Transfer availability is per-experience; the option is hidden when not allowed',
    ],
  },

  // ────────────────────────────── Shotgun ────────────────────────────────────
  shotgun: {
    platform: 'shotgun',
    displayName: 'Shotgun',
    icon: '\u{1F39B}️',
    transferMethods: ['mobile_transfer'],
    seller: {
      title: 'How to transfer tickets on Shotgun',
      steps: [
        'Open the Shotgun app → "My tickets"',
        'Open the ticket QR and tap "Transfer"',
        'Choose "Send as a gift" → "Transfer ticket"',
        'Share the transfer link with the buyer through Snatch It chat',
        'Screenshot the "Pending transfer" state',
      ],
      tips: [
        'The QR shows "Pending transfer" until the buyer accepts, then greys out as "Transferred"',
        'You can cancel only BEFORE the buyer accepts',
      ],
      estimatedTime: '2-3 minutes',
    },
    buyer: {
      title: 'How to receive tickets on Shotgun',
      steps: [
        'Open the transfer link from the seller',
        'Log in / create a Shotgun account in the app',
        'Accept the transfer — the ticket moves to your "My tickets"',
      ],
      tips: [
        'Once you accept, only you can transfer it onward',
      ],
      estimatedTime: '1-2 minutes',
    },
    warnings: [
      'Organizers can block transfers/resale per event — verify the Transfer button exists before listing',
    ],
  },

  // ────────────────────────────── Universe ───────────────────────────────────
  universe: {
    platform: 'universe',
    displayName: 'Universe',
    icon: '\u{1FA90}',
    transferMethods: ['email'],
    seller: {
      title: 'How to transfer tickets on Universe',
      steps: [
        'Log in to your Universe account and find the ticket',
        'Tap "More" (next to View Ticket) → "Transfer Ticket"',
        'Enter the buyer\'s first name, last name, and email: {buyer_email}',
        'Confirm the transfer (tickets transfer one at a time)',
        'Screenshot the confirmation',
      ],
      tips: [
        'For multiple tickets, repeat the transfer for each one',
      ],
      estimatedTime: '3-5 minutes',
    },
    buyer: {
      title: 'How to receive tickets on Universe',
      steps: [
        'Open the "Confirm Your Ticket Transfer" email',
        'Authenticate / sign in and accept',
        'The ticket is released into your Universe account',
      ],
      tips: [
        'Use the same email the seller entered',
      ],
      estimatedTime: '1-2 minutes',
    },
    warnings: [
      'Per Universe: transfers are IRREVERSIBLE and the order becomes non-refundable after transfer',
      'Organizers can disable transfers at any time',
    ],
  },

  // ──────────────────────────── See Tickets ──────────────────────────────────
  see_tickets: {
    platform: 'see_tickets',
    displayName: 'See Tickets',
    icon: '\u{1F441}️',
    transferMethods: ['email'],
    seller: {
      title: 'How to share tickets on See Tickets',
      steps: [
        'Log in to your See Tickets account (only the original purchaser can share)',
        'Open your digital ticket wallet — the share button is next to the ticket',
        'Use the ticket share tool to send the ticket to the buyer\'s account email: {buyer_email}',
        'Screenshot the confirmation',
      ],
      tips: [
        'Digital tickets typically appear about one week before the event — you may need to wait before sharing',
        'You can reclaim a shared ticket and re-share it to someone else if needed',
      ],
      estimatedTime: '3-5 minutes',
    },
    buyer: {
      title: 'How to receive tickets on See Tickets',
      steps: [
        'Create / sign in to a See Tickets account with the email you provided',
        'Accept the shared ticket — it appears in your digital wallet',
      ],
      tips: [
        'Note: tickets shared to you cannot be re-shared onward — only the original purchaser can share',
      ],
      estimatedTime: '1-2 minutes',
    },
    warnings: [
      'Some events restrict sharing in their terms — sellers should confirm the share button exists before listing',
    ],
  },

  // ──────────────────────────── MLB Ballpark ─────────────────────────────────
  // Miami note: Marlins / loanDepot park tickets live in the MLB Ballpark app.
  mlb_ballpark: {
    platform: 'mlb_ballpark',
    displayName: 'MLB Ballpark',
    icon: '⚾',
    transferMethods: ['mobile_transfer', 'email'],
    seller: {
      title: 'How to forward tickets in the MLB Ballpark app',
      steps: [
        'Open the MLB Ballpark app → Tickets tab → tap the game',
        'Tap "Forward Ticket" at the bottom',
        'Select the ticket(s)',
        'Choose "Via Email" and enter: {buyer_email} (contacts or a Share Link also work)',
        'Send, then screenshot the confirmation',
      ],
      tips: [
        'Forwarding works from purchase until 2 hours after first pitch, as long as the ticket hasn\'t been scanned',
        'If you use a Share Link, the FIRST person to accept gets the ticket — only share it privately with your buyer',
      ],
      estimatedTime: '2-4 minutes',
    },
    buyer: {
      title: 'How to receive tickets in the MLB Ballpark app',
      steps: [
        'Tap "Accept" in the forward email (or open the share link)',
        'Sign in / create a free MLB account and install the MLB Ballpark app',
        'The tickets appear in your Tickets tab',
      ],
      tips: [
        'Apple Wallet is supported for entry; Google Pay is not',
      ],
      estimatedTime: '1-2 minutes',
    },
    warnings: [
      'Per MLB: the sender can RECALL a forwarded ticket any time before it\'s scanned — even after you accept. Confirm receipt in Snatch It only after the tickets are in your account, and report immediately if they disappear',
    ],
  },

  // ────────────────────────────── StubHub ────────────────────────────────────
  // Source-platform: tickets a seller previously bought on StubHub.
  stubhub: {
    platform: 'stubhub',
    displayName: 'StubHub (purchased there)',
    icon: '\u{1F39F}️',
    transferMethods: ['mobile_transfer', 'email'],
    seller: {
      title: 'How to re-send tickets you bought on StubHub',
      steps: [
        'Check how StubHub delivered your tickets:',
        'If they arrived in your Ticketmaster/AXS/DICE account → transfer them from THAT platform (select it as the platform when listing)',
        'If they live in the StubHub app → open the order and use "Manage Transfers"',
        'Enter the buyer\'s email: {buyer_email} and confirm',
        'Screenshot the confirmation',
      ],
      tips: [
        'No "Manage Transfers" button on a StubHub app ticket = that ticket is NOT transferable — do not list it',
      ],
      estimatedTime: '3-6 minutes',
    },
    buyer: {
      title: 'How to receive StubHub-sourced tickets',
      steps: [
        'Follow the acceptance email from the delivering platform (StubHub, Ticketmaster, AXS, or DICE)',
        'Create the matching account with the email you provided and accept',
      ],
      tips: [
        'Ask the seller which app the ticket will arrive in before the transfer',
      ],
      estimatedTime: '2-3 minutes',
    },
    warnings: [
      'Per StubHub: screenshots are acceptable ONLY for static barcodes — rotating barcodes must be shown live in the app',
    ],
  },

  // ───────────────────────────── Vivid Seats ─────────────────────────────────
  vivid_seats: {
    platform: 'vivid_seats',
    displayName: 'Vivid Seats (purchased there)',
    icon: '\u{1F3DF}️',
    transferMethods: ['mobile_transfer', 'email'],
    seller: {
      title: 'How to re-send tickets you bought on Vivid Seats',
      steps: [
        'Check the delivery method on your Vivid Seats order:',
        'Electronic Transfer tickets → they live in the external account (e.g. Ticketmaster) where you accepted them; transfer from there using the Transfer button',
        'PDF / Instant Download tickets → the file itself is the ticket (static barcode)',
        'Send to the buyer\'s email: {buyer_email}',
        'Screenshot the confirmation',
      ],
      tips: [
        'For Electronic Transfer tickets, list the actual wallet platform (e.g. Ticketmaster) instead so the buyer gets the right instructions',
      ],
      estimatedTime: '3-6 minutes',
    },
    buyer: {
      title: 'How to receive Vivid Seats-sourced tickets',
      steps: [
        'Accept the transfer in the platform the seller names (often Ticketmaster), or receive the PDF',
        'For PDFs: the first scan at the door wins — make sure the seller sends it only to you',
      ],
      tips: [
        'Confirm with the seller exactly which app or file format to expect',
      ],
      estimatedTime: '2-3 minutes',
    },
    warnings: [
      'Rotating-barcode tickets inherit the rules of the delivering platform — screenshots won\'t scan there',
    ],
  },

  // ────────────────────────────── Gametime ───────────────────────────────────
  gametime: {
    platform: 'gametime',
    displayName: 'Gametime (purchased there)',
    icon: '⏱️',
    transferMethods: ['mobile_transfer', 'email'],
    seller: {
      title: 'How to re-send tickets you bought on Gametime',
      steps: [
        'Check where your Gametime tickets live:',
        'Delivered via Ticketmaster/AXS/SeatGeek/MLB Ballpark → transfer from that platform (select it when listing)',
        'In-app Gametime barcode → use Gametime\'s in-app share (text/email) to: {buyer_email}',
        'Screenshot the confirmation',
      ],
      tips: [
        'In-app Gametime barcodes stay inside Gametime — the buyer will need the Gametime app',
      ],
      estimatedTime: '3-6 minutes',
    },
    buyer: {
      title: 'How to receive Gametime-sourced tickets',
      steps: [
        'Follow the share/transfer notification (Gametime app, or the external platform the seller names)',
        'Create the matching account and accept',
      ],
      tips: [
        'Ask the seller which app the ticket arrives in before they send',
      ],
      estimatedTime: '2-3 minutes',
    },
    warnings: [
      'In-app Gametime barcodes cannot be moved into Ticketmaster/AXS wallets',
    ],
  },

  // ─────────────────────────────── Other ─────────────────────────────────────
  other: {
    platform: 'other',
    displayName: 'Other Platform',
    icon: '\u{1F4E7}',
    transferMethods: ['email', 'mobile_transfer'],
    seller: {
      title: 'How to transfer your tickets',
      steps: [
        'Open the app or website where you purchased the tickets',
        'Find the official ticket transfer / send / share option',
        'Enter the buyer\'s contact info as provided',
        'Complete the transfer',
        'Take a screenshot of the confirmation',
      ],
      tips: [
        'Festival platforms (e.g. Front Gate for III Points / Rolling Loud, Ultra\'s own system) each have their own official process — follow it exactly',
        'If the platform doesn\'t support transfer, contact the event organizer before listing',
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
        'Contact the seller via Snatch It if you haven\'t received anything within 2 hours',
      ],
      estimatedTime: 'Varies',
    },
    warnings: [
      'Transfer process varies by platform. Only accept the ticket through the platform\'s official transfer — never rely on a screenshot of a barcode. If you have issues, open a dispute.',
    ],
  },
};
