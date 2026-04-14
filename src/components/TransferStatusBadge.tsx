import { StyleSheet, Text, View } from 'react-native';
import { fontSize, radius, spacing } from '@/src/theme';
import type { TransferStatus } from '@/src/types';

const config: Record<TransferStatus, { bg: string; text: string; label: string }> = {
  pending:          { bg: 'rgba(251,191,36,0.15)', text: '#fbbf24', label: 'Transfer Pending' },
  seller_sent:      { bg: 'rgba(96,165,250,0.15)',  text: '#60a5fa', label: 'Transfer Sent' },
  buyer_confirmed:  { bg: 'rgba(74,222,128,0.15)',  text: '#4ade80', label: 'Transfer Complete' },
  disputed:         { bg: 'rgba(255,77,109,0.15)',   text: '#ff4d6d', label: 'Disputed' },
  expired:          { bg: 'rgba(138,148,166,0.15)',  text: '#8a94a6', label: 'Transfer Expired' },
  auto_released:    { bg: 'rgba(74,222,128,0.15)',  text: '#4ade80', label: 'Auto-Released' },
};

type Props = { status: TransferStatus | null | undefined };

export default function TransferStatusBadge({ status }: Props) {
  if (!status || !config[status]) return null;

  const c = config[status];

  return (
    <View style={[s.badge, { backgroundColor: c.bg }]}>
      <Text style={[s.text, { color: c.text }]}>{c.label}</Text>
    </View>
  );
}

const s = StyleSheet.create({
  badge: { alignSelf: 'flex-start', paddingHorizontal: spacing.sm, paddingVertical: spacing.xs, borderRadius: radius.full },
  text:  { fontSize: fontSize.xs, fontWeight: '700' },
});
