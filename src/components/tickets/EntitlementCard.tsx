/**
 * src/components/tickets/EntitlementCard.tsx — one admission entitlement (one kernel ticket atom).
 *
 * The card says what the server said (entitlement.ts maps the atom facts to a badge and a line)
 * and draws a code ONLY when a server credential is in hand (`credential.kind === 'ready'`). A
 * ready atom without a credential yet shows the pinned loading / refusal copy and a way to ask
 * again; a used, revoked, expired, held or unknown atom never asks.
 */
import { memo, useMemo } from 'react';
import { StyleSheet, Text, View } from 'react-native';

import { Badge, Button, Spinner, type BadgeTone } from '@/src/components/ui';
import {
  CREDENTIAL_COPY,
  ENTITLEMENT_COPY,
  canRequestCredential,
  entitlementDisplay,
  type CredentialState,
  type EntitlementDisplay,
  type MyTicketAtom,
} from '@/src/lib/tickets/entitlement';
import { textStyle } from '@/src/theme/typography';
import { useTheme } from '@/src/theme/appearance';
import type { Palette } from '@/src/theme/palette';
import * as v2 from '@/src/theme/v2';

import { TicketQR } from './TicketQR';

const TONE: Record<EntitlementDisplay, BadgeTone> = {
  ready: 'success',
  used: 'neutral',
  revoked: 'danger',
  expired: 'neutral',
  held: 'warning',
  unknown: 'warning',
};

/** Refusals a tap can do nothing about: no retry button, just the sentence. */
const NO_RETRY: ReadonlySet<string> = new Set(['not_owner', 'atom_terminal']);

export const ENTITLEMENT_ACTIONS = {
  show: 'Show entry code',
  refresh: 'Refresh code',
  retry: 'Try again',
  loading: 'Loading entry code',
} as const;

export function entitlementHeading(index: number, total: number): string {
  return total > 1 ? `Ticket ${index + 1} of ${total}` : 'Your ticket';
}

export const EntitlementCard = memo(function EntitlementCard({
  atom,
  index,
  total,
  credential,
  qrSize,
  onShowCode,
  onEncodeFailure,
}: {
  atom: MyTicketAtom;
  index: number;
  total: number;
  credential: CredentialState;
  qrSize: number;
  onShowCode: () => void;
  onEncodeFailure: () => void;
}) {
  const { palette } = useTheme();
  const s = useMemo(() => makeStyles(palette), [palette]);
  const display = entitlementDisplay(atom);
  const copy = ENTITLEMENT_COPY[display];
  const heading = entitlementHeading(index, total);
  const qrLabel = `Entry code, ${heading}, ${atom.ticket_type_name}`;

  return (
    <View style={s.card} accessibilityLabel={`${heading}, ${atom.ticket_type_name}, ${copy.badge}`}>
      <View style={s.head}>
        <View style={s.headText}>
          <Text style={[textStyle('title'), s.heading]}>{heading}</Text>
          <Text style={[textStyle('bodySm'), s.type]}>{atom.ticket_type_name}</Text>
        </View>
        <Badge label={copy.badge} tone={TONE[display]} />
      </View>

      {canRequestCredential(display) ? (
        <View style={s.codeArea}>
          {credential.kind === 'ready' ? (
            <TicketQR token={credential.credential.token} label={qrLabel} size={qrSize} onEncodeFailure={onEncodeFailure} />
          ) : credential.kind === 'minting' ? (
            <View style={[s.placeholder, { width: qrSize, height: qrSize }]}>
              <Spinner label={ENTITLEMENT_ACTIONS.loading} />
            </View>
          ) : credential.kind === 'refused' ? (
            <View style={s.refusal}>
              <Text style={[textStyle('body'), s.refusalText]} accessibilityRole="alert">
                {CREDENTIAL_COPY[credential.reason]}
              </Text>
              {NO_RETRY.has(credential.reason) ? null : (
                <Button label={ENTITLEMENT_ACTIONS.retry} variant="secondary" size="md" onPress={onShowCode} />
              )}
            </View>
          ) : (
            <Button label={ENTITLEMENT_ACTIONS.show} variant="primary" size="md" onPress={onShowCode} />
          )}
          <Text style={[textStyle('bodySm'), s.body]}>{copy.body}</Text>
          {credential.kind === 'ready' ? (
            <Button label={ENTITLEMENT_ACTIONS.refresh} variant="ghost" size="sm" onPress={onShowCode} />
          ) : null}
        </View>
      ) : (
        <Text style={[textStyle('bodySm'), s.body]}>{copy.body}</Text>
      )}
    </View>
  );
});

function makeStyles(p: Palette) {
  return StyleSheet.create({
    card: {
      backgroundColor: p.surface.surface,
      borderRadius: v2.radius.md,
      padding: v2.space.lg,
      gap: v2.space.md,
    },
    head: { flexDirection: 'row', alignItems: 'flex-start', justifyContent: 'space-between', gap: v2.space.sm },
    headText: { flexShrink: 1, gap: 2 },
    heading: { color: p.text.primary },
    type: { color: p.text.secondary },
    codeArea: { alignItems: 'center', gap: v2.space.md },
    placeholder: {
      backgroundColor: p.surface.elevated,
      borderRadius: v2.radius.md,
      alignItems: 'center',
      justifyContent: 'center',
    },
    refusal: { alignItems: 'center', gap: v2.space.sm, paddingVertical: v2.space.md },
    refusalText: { color: p.text.primary, textAlign: 'center' },
    body: { color: p.text.secondary, textAlign: 'center' },
  });
}
