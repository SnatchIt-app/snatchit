/**
 * src/components/SecurityNoticeBanner.tsx — the account-security notice on the
 * first signed-in screen (mounted by the tabs layout only; never on the login
 * screen, K-2). Title and body are the server's; the client owns only the two
 * action labels.
 */

import { useEffect, useMemo } from 'react';
import { AccessibilityInfo, StyleSheet, Text, View } from 'react-native';

import { Button } from '@/src/components/ui/Button';
import { useAuth } from '@/src/hooks/useAuth';
import { useSecurityNotices } from '@/src/hooks/useSecurityNotices';
import { actionsFor, NOTICE_ACTION_LABEL } from '@/src/lib/security/notices';
import { useTopInset } from '@/src/lib/nav/navInsets';
import { textStyle } from '@/src/theme/typography';
import { useTheme } from '@/src/theme/appearance';
import type { Palette } from '@/src/theme/palette';
import * as v2 from '@/src/theme/v2';

export function SecurityNoticeBanner() {
  const { palette } = useTheme();
  const s = useMemo(() => makeStyles(palette), [palette]);
  const { user } = useAuth();
  const { notice, busy, error, dismiss, signOutAll } = useSecurityNotices(user?.id);
  // Mounted above <Tabs>, so it is the topmost element and pays the top inset itself
  // (status bar + the SANDBOX badge on sandbox builds) like every tab screen does —
  // otherwise the title sits under the badge (F-SELL-1 again; D, 2026-09-18). Interim:
  // the screen below still pays its own inset while the banner shows (a double gap);
  // an overlay like SandboxBadge is the tidier follow-up.
  const top = useTopInset();

  useEffect(() => {
    if (notice) AccessibilityInfo.announceForAccessibility(`${notice.title}. ${notice.body}`);
  }, [notice?.id]); // eslint-disable-line react-hooks/exhaustive-deps

  if (!notice) return null;
  const actions = actionsFor(notice.type_key);

  return (
    <View style={[s.wrap, { paddingTop: top + v2.space.md }]} accessibilityRole="alert">
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

function makeStyles(p: Palette) {
  return StyleSheet.create({
  wrap: { paddingHorizontal: v2.space.lg, paddingVertical: v2.space.md, backgroundColor: p.surface.elevated, borderBottomWidth: 1, borderBottomColor: p.status.warning, gap: v2.space.xs },
  title: { color: p.text.primary, fontWeight: '700' },
  body: { color: p.text.secondary },
  error: { color: p.status.error },
  actions: { flexDirection: 'row', flexWrap: 'wrap', gap: v2.space.sm, marginTop: v2.space.xs },
  });
}
