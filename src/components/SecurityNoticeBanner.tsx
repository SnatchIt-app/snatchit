/**
 * src/components/SecurityNoticeBanner.tsx — the account-security notice on the
 * first signed-in screen (mounted by the tabs layout only; never on the login
 * screen, K-2). Title and body are the server's; the client owns only the two
 * action labels.
 */

import { useEffect } from 'react';
import { AccessibilityInfo, StyleSheet, Text, View } from 'react-native';

import { Button } from '@/src/components/ui/Button';
import { useAuth } from '@/src/hooks/useAuth';
import { useSecurityNotices } from '@/src/hooks/useSecurityNotices';
import { actionsFor, NOTICE_ACTION_LABEL } from '@/src/lib/security/notices';
import { textStyle } from '@/src/theme/typography';
import * as v2 from '@/src/theme/v2';

export function SecurityNoticeBanner() {
  const { user } = useAuth();
  const { notice, busy, error, dismiss, signOutAll } = useSecurityNotices(user?.id);

  useEffect(() => {
    if (notice) AccessibilityInfo.announceForAccessibility(`${notice.title}. ${notice.body}`);
  }, [notice?.id]); // eslint-disable-line react-hooks/exhaustive-deps

  if (!notice) return null;
  const actions = actionsFor(notice.type_key);

  return (
    <View style={s.wrap} accessibilityRole="alert">
      <Text style={[textStyle('title'), s.title]} accessibilityRole="header">{notice.title}</Text>
      <Text style={[textStyle('bodySm'), s.body]}>{notice.body}</Text>
      {error ? <Text style={[textStyle('bodySm'), s.error]}>{error}</Text> : null}
      <View style={s.actions}>
        {actions.includes('sign_out_all') ? (
          <Button label={NOTICE_ACTION_LABEL.sign_out_all} variant="secondary" onPress={signOutAll} loading={busy} disabled={busy} />
        ) : null}
        <Button label={NOTICE_ACTION_LABEL.dismiss} variant="secondary" onPress={dismiss} disabled={busy} />
      </View>
    </View>
  );
}

const s = StyleSheet.create({
  wrap: { paddingHorizontal: v2.space.lg, paddingVertical: v2.space.md, backgroundColor: v2.surface.elevated, borderBottomWidth: 1, borderBottomColor: v2.status.warning, gap: v2.space.xs },
  title: { color: v2.text.primary, fontWeight: '700' },
  body: { color: v2.text.secondary },
  error: { color: v2.status.error },
  actions: { flexDirection: 'row', flexWrap: 'wrap', gap: v2.space.sm, marginTop: v2.space.xs },
});
