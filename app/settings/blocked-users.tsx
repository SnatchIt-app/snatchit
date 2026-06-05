/**
 * app/settings/blocked-users.tsx — list + unblock.
 *
 * Apple's Guideline 1.2 requires that users can block abusive accounts.
 * It does not strictly require an unblock UI, but providing one removes
 * the "blocked forever" concern App Reviewers sometimes flag.
 *
 * Reads public.user_blocks (RLS scoped to the caller's row) and joins
 * public.profiles to show a friendly display_name for each blocked user.
 */
import { router } from 'expo-router';
import { useCallback, useEffect, useState } from 'react';
import { useFocusEffect } from '@react-navigation/native';
import {
  ActivityIndicator,
  Alert,
  FlatList,
  Pressable,
  RefreshControl,
  StyleSheet,
  Text,
  TouchableOpacity,
  View,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';

import { supabase } from '@/src/lib/supabase';
import { useAuth } from '@/src/hooks/useAuth';
import { colors, fontSize, radius, spacing } from '@/src/theme';

type Row = {
  blocked_id: string;
  created_at: string;
  blocked:    { display_name: string | null } | null;
};

export default function BlockedUsersScreen() {
  const { user } = useAuth();
  const userId   = user?.id ?? null;
  const [rows, setRows] = useState<Row[]>([]);
  const [loading,    setLoading]    = useState(true);
  const [refreshing, setRefreshing] = useState(false);

  // Two-step fetch — user_blocks.blocked_id FK points to auth.users(id),
  // NOT public.profiles(id), so PostgREST cannot resolve the embed.
  //   1) read user_blocks where blocker_id = me
  //   2) read profiles where id IN (...) — tolerate failures
  // Always sets loading=false on every exit path so the spinner can never
  // stick.  Console-logs every shape so we can verify in the device console
  // exactly what the API returns.
  // Dev/preview-only debug logger so device console stays clean in production.
  const isDev = process.env.EXPO_PUBLIC_APP_ENV !== 'production';
  const dlog = (...args: unknown[]) => { if (isDev) console.log(...args); };

  const fetchRows = useCallback(async () => {
    if (!userId) {
      dlog('[blocked-users] fetchRows skipped — no user yet');
      setLoading(false);   // ← never let spinner stick when auth is delayed
      return;
    }
    try {
      const { data: blocks, error: blocksErr } = await supabase
        .from('user_blocks')
        .select('blocked_id, created_at')
        .eq('blocker_id', userId)
        .order('created_at', { ascending: false });

      dlog('[blocked-users] user_blocks fetched:',
        { count: blocks?.length ?? 0, error: blocksErr?.message ?? null });

      if (blocksErr) {
        setRows([]);
        return;
      }
      const blockRows = (blocks ?? []) as { blocked_id: string; created_at: string }[];

      if (blockRows.length === 0) {
        setRows([]);
        return;
      }

      const ids = blockRows.map(r => r.blocked_id);
      const profileMap = new Map<string, string | null>();
      const { data: profs, error: profsErr } = await supabase
        .from('profiles')
        .select('id, display_name')
        .in('id', ids);
      dlog('[blocked-users] profiles fetched:',
        { count: profs?.length ?? 0, error: profsErr?.message ?? null });
      for (const p of (profs ?? []) as { id: string; display_name: string | null }[]) {
        profileMap.set(p.id, p.display_name);
      }

      const merged: Row[] = blockRows.map(b => ({
        blocked_id: b.blocked_id,
        created_at: b.created_at,
        blocked:    { display_name: profileMap.get(b.blocked_id) ?? null },
      }));
      dlog('[blocked-users] rendering rows:', merged.length);
      setRows(merged);
    } catch (e) {
      console.warn('[blocked-users] unexpected error:', e);
      setRows([]);
    } finally {
      setLoading(false);
    }
  }, [userId, isDev]); // eslint-disable-line react-hooks/exhaustive-deps

  // Hard load on mount AND every time userId changes from null → set.
  useEffect(() => { fetchRows(); }, [fetchRows]);

  // Refetch every time the screen regains focus (catches: user blocked
  // someone, then navigated here. Without focus-refresh, an initial mount
  // before block insert would show stale empty state.)
  useFocusEffect(
    useCallback(() => {
      fetchRows();
    }, [fetchRows]),
  );

  async function onRefresh() {
    setRefreshing(true);
    await fetchRows();
    setRefreshing(false);
  }

  async function handleUnblock(blockedId: string, displayName: string) {
    Alert.alert(
      'Unblock user?',
      `${displayName} will be able to appear in your feeds again.`,
      [
        { text: 'Cancel', style: 'cancel' },
        {
          text: 'Unblock',
          style: 'destructive',
          onPress: async () => {
            const { error } = await supabase
              .from('user_blocks')
              .delete()
              .eq('blocker_id', user!.id)
              .eq('blocked_id', blockedId);
            if (error) {
              Alert.alert('Could not unblock', error.message);
              return;
            }
            // Optimistic local update + authoritative refresh to keep server
            // truth in sync if RLS / triggers ever change behavior.
            setRows(prev => prev.filter(r => r.blocked_id !== blockedId));
            fetchRows();
          },
        },
      ],
    );
  }

  return (
    <SafeAreaView style={s.safe}>
      <View style={s.topBar}>
        <Pressable onPress={() => router.back()} style={s.backBtn} hitSlop={8}>
          <Text style={s.backArrow}>{'←'}</Text>
        </Pressable>
        <Text style={s.topTitle}>Blocked Users</Text>
        <View style={s.backBtn} />
      </View>

      {loading ? (
        <View style={s.center}><ActivityIndicator color={colors.accent} /></View>
      ) : rows.length === 0 ? (
        <FlatList
          // Wrap empty state in a FlatList so it gets pull-to-refresh too —
          // critical recovery path if the first fetch raced auth init.
          contentContainerStyle={[s.list, { flexGrow: 1 }]}
          data={[]}
          keyExtractor={(_, i) => String(i)}
          renderItem={null as any}
          refreshControl={<RefreshControl refreshing={refreshing} onRefresh={onRefresh} tintColor={colors.accent} />}
          ListEmptyComponent={
            <View style={s.center}>
              <Text style={s.emptyTitle}>No one blocked</Text>
              <Text style={s.emptyBody}>
                Users you block from a listing will appear here. You can unblock
                them anytime. Pull down to refresh.
              </Text>
            </View>
          }
        />
      ) : (
        <FlatList
          contentContainerStyle={s.list}
          data={rows}
          keyExtractor={(r) => r.blocked_id}
          ItemSeparatorComponent={() => <View style={s.sep} />}
          refreshControl={<RefreshControl refreshing={refreshing} onRefresh={onRefresh} tintColor={colors.accent} />}
          renderItem={({ item }) => {
            // Fallback label per QA: when profile join is missing/null, show
            // "Blocked user" so the row + Unblock button are always actionable.
            const name = item.blocked?.display_name?.trim() || 'Blocked user';
            return (
              <View style={s.row}>
                <View style={{ flex: 1 }}>
                  <Text style={s.name}>{name}</Text>
                  <Text style={s.meta}>
                    Blocked {new Date(item.created_at).toLocaleDateString()}
                  </Text>
                </View>
                <TouchableOpacity
                  style={s.unblockBtn}
                  onPress={() => handleUnblock(item.blocked_id, name)}
                  activeOpacity={0.85}
                >
                  <Text style={s.unblockText}>Unblock</Text>
                </TouchableOpacity>
              </View>
            );
          }}
        />
      )}
    </SafeAreaView>
  );
}

const s = StyleSheet.create({
  safe:     { flex: 1, backgroundColor: colors.bg },
  topBar:   {
    flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between',
    paddingHorizontal: spacing.md, paddingVertical: spacing.sm,
    borderBottomWidth: 1, borderBottomColor: colors.border,
  },
  backBtn:  { width: 44, height: 44, alignItems: 'flex-start', justifyContent: 'center' },
  backArrow:{ color: colors.text, fontSize: fontSize.xl, fontWeight: '600' },
  topTitle: { color: colors.text, fontSize: fontSize.md, fontWeight: '700' },

  center:   { flex: 1, alignItems: 'center', justifyContent: 'center', padding: spacing.xl },
  emptyTitle: { color: colors.text, fontSize: fontSize.md, fontWeight: '700', marginBottom: spacing.sm },
  emptyBody:  { color: colors.textMuted, fontSize: fontSize.sm, textAlign: 'center', lineHeight: 20, maxWidth: 320 },

  list:     { paddingHorizontal: spacing.lg, paddingTop: spacing.md, paddingBottom: spacing.xxl },
  row:      { flexDirection: 'row', alignItems: 'center', paddingVertical: spacing.md },
  sep:      { height: 1, backgroundColor: colors.border },
  name:     { color: colors.text, fontSize: fontSize.md, fontWeight: '600' },
  meta:     { color: colors.textMuted, fontSize: fontSize.xs, marginTop: 2 },
  unblockBtn:  { borderWidth: 1, borderColor: colors.border, paddingHorizontal: spacing.md, paddingVertical: spacing.sm, borderRadius: radius.md },
  unblockText: { color: colors.text, fontSize: fontSize.sm, fontWeight: '600' },
});
