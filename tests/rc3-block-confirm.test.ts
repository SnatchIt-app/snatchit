/**
 * tests/rc3-block-confirm.test.ts — RC3 S5: K1 is the block confirmation wherever a block is offered,
 * and the two order screens offer one without touching the order.
 */
import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';

import { BLOCK_CONFIRM_BODY, blockConfirmMessage } from '@/src/lib/moderation/blockCopy';

const K1 = "You won't see their listings in Home or Search, and neither of you will be able to bid on or buy the other's listings. Orders you already have together aren't affected, and you can still report them.";

const strip = (rel: string) => readFileSync(rel, 'utf8')
  .replace(/\/\*[\s\S]*?\*\//g, '').replace(/(^|[^:])\/\/.*$/gm, '$1');

describe('RC3 · K1 block confirmation', () => {
  it('BK1: the module holds K1 verbatim and the message starts with it', () => {
    expect(BLOCK_CONFIRM_BODY).toBe(K1);
    expect(blockConfirmMessage().startsWith(K1)).toBe(true);
  });

  it('BK2: listing detail and profile confirm with K1; the old feed-only sentence is gone from both', () => {
    for (const rel of ['src/screens/ListingDetailScreen.tsx', 'app/profile/[id].tsx']) {
      const src = strip(rel);
      expect(src, rel).toContain('blockConfirmMessage()');
      expect(src, rel).not.toContain('Their listings will be hidden from your feed.');
    }
  });

  it('BK3: transfer/receive and transfer/send offer a Block entry that confirms with K1', () => {
    for (const rel of ['app/transfer/receive/[id].tsx', 'app/transfer/send/[id].tsx']) {
      const src = strip(rel);
      expect(src, rel).toContain("from '@/src/lib/moderation/blockFlow'");
      expect(src, rel).toMatch(/label: `Block \$\{/);
      expect(src, rel).toContain('glyph="more"');
    }
  });

  it('BK4: blocking from an order screen writes user_blocks only — never a transfer, never an RPC, never navigation', () => {
    const flow = strip('src/lib/moderation/blockFlow.ts');
    expect(flow).toContain("from('user_blocks')");
    expect(flow).not.toContain("from('transfers')");
    expect(flow).not.toContain('.rpc(');
    expect(flow).not.toContain('router.');
    expect(flow).toContain('blockConfirmMessage()');
    // 23505 (already blocked) is a success, as on the other two screens.
    expect(flow).toContain("'23505'");
  });
});

describe('RC3 · the harness can paint the new surfaces without a sign-in or a write', () => {
  it('BK5: the order fixtures carry the counterparty id, and the Block press is write:false under a fixture', () => {
    const tickets = strip('app/_dev/v3-tickets.tsx');
    expect(tickets).toContain("seller_id: 'fixture-seller'");
    expect(tickets).toContain("buyer_id: 'fixture-buyer'");
    for (const rel of ['app/transfer/receive/[id].tsx', 'app/transfer/send/[id].tsx']) {
      expect(strip(rel), rel).toContain('write: !fixture');
    }
  });

  it('BK6: the account harness mounts the Legal screen (screen=legal)', () => {
    const account = strip('app/_dev/v3-account.tsx');
    expect(account).toContain("case 'legal':");
    expect(account).toContain('<LegalScreen />');
  });
});
