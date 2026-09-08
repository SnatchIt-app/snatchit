/**
 * app/settings/blocked-users.tsx — list + unblock (V2).
 *
 * PRESENTATION rebuilt on the V2 system; behaviour is unchanged. The two-step
 * fetch (user_blocks → profiles), the focus refetch and pull-to-refresh, and the
 * unblock confirm + delete + refresh are preserved. The critical safety
 * distinction stays: a FAILED load ("couldn't check") is never rendered as "no one
 * blocked" — a block list that reports the opposite of the truth is worse than one
 * that admits it could not load.
 */

import { useCallback, useEffect, useState } from 'react';
import { useFocusEffect } from '@react-navigation/native';
import { Alert, FlatList, RefreshControl, StyleSheet, Text, View } from 'react-native';

import { supabase } from '@/src/lib/supabase';
import { useAuth } from '@/src/hooks/useAuth';
import { Button, EmptyState, Spinner } from '@/src/components/ui';
import { SettingsHeader } from '@/src/components/account/SettingsHeader';
import { textStyle } from '@/src/theme/typography';
import * as v2 from '@/src/theme/v2';

type Row = {
  blocked_id: string;
  created_at: string;
  blocked: { display_name: string | null } | null;
};

export default function BlockedUsersScreen() {
  const { user } = useAuth();
  const userId = user?.id ?? null;
  const [rows, setRows] = useState<Row[]>([]);
  // A FAILED load is distinct from "nobody blocked".
  const [loadFailed, setLoadFailed] = useState(false);
  const [loading, setLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);

  const isDev = process.env.EXPO_PUBLIC_APP_ENV !== 'production';
  const dlog = (...args: unknown[]) => { if (isDev) console.log(...args); };

  const fetchRows = useCallback(async () => {
    if (!userId) { dlog('[blocked-users] fetchRows skipped — no user yet'); setLoading(false); return; }
    try {
      setLoadFailed(false);
      const { data: blocks, error: blocksErr } = await supabase
        .from('user_blocks')
        .select('blocked_id, created_at')
        .eq('blocker_id', userId)
        .order('created_at', { ascending: false });

      dlog('[blocked-users] user_blocks fetched:', { count: blocks?.length ?? 0, error: blocksErr?.message ?? null });

      if (blocksErr) {
        console.warn('[blocked-users] user_blocks fetch failed:', blocksErr.message);
        setRows([]);
        setLoadFailed(true);
        return;
      }
      const blockRows = (blocks ?? []) as { blocked_id: string; created_at: string }[];
      if (blockRows.length === 0) { setRows([]); setLoadFailed(false); return; }

      const ids = blockRows.map((r) => r.blocked_id);
      const profileMap = new Map<string, string | null>();
      const { data: profs, error: profsErr } = await supabase.from('profiles').select('id, display_name').in('id', ids);
      dlog('[blocked-users] profiles fetched:', { count: profs?.length ?? 0, error: profsErr?.message ?? null });
      for (const p of (profs ?? []) as { id: string; display_name: string | null }[]) {
        profileMap.set(p.id, p.display_name);
      }

      const merged: Row[] = blockRows.map((b) => ({
        blocked_id: b.blocked_id,
        created_at: b.created_at,
        blocked: { display_name: profileMap.get(b.blocked_id) ?? null },
      }));
      setRows(merged);
      setLoadFailed(false);
    } catch (e) {
      console.warn('[blocked-users] unexpected error:', e);
      setRows([]);
      setLoadFailed(true);
    } finally {
      setLoading(false);
    }
  }, [userId, isDev]); // eslint-disable-line react-hooks/exhaustive-deps

  useEffect(() => { fetchRows(); }, [fetchRows]);
  useFocusEffect(useCallback(() => { fetchRows(); }, [fetchRows]));

  async function onRefresh() {
    setRefreshing(true);
    await fetchRows();
    setRefreshing(false);
  }

  async function handleUnblock(blockedId: string, displayName: string) {
    Alert.alert('Unblock user?', `${displayName} will be able to appear in your feeds again.`, [
      { text: 'Cancel', style: 'cancel' },
      {
        text: 'Unblock',
        style: 'destructive',
        onPress: async () => {
          const { error } = await supabase.from('user_blocks').delete().eq('blocker_id', user!.id).eq('blocked_id', blockedId);
          if (error) { Alert.alert('Could not unblock', error.message); return; }
          setRows((prev) => prev.filter((r) => r.blocked_id !== blockedId));
          fetchRows();
        },
      },
    ]);
  }

  return (
    <View style={s.root}>
      <SettingsHeader title="Blocked users" />
      {loading ? (
        <View style={s.center}><Spinner color={v2.brand.red} /></View>
      ) : loadFailed && rows.length === 0 ? (
        <View style={s.center}>
          <Text style={[textStyle('title'), s.failTitle]}>Couldn&apos;t load your block list</Text>
          <Text style={[textStyle('bodySm'), s.failBody]}>
            This is not a record that you have blocked no one. Check your connection and try again.
          </Text>
          <Button label="Retry" variant="secondary" onPress={() => { setLoading(true); fetchRows(); }} style={s.retry} />
        </View>
      ) : rows.length === 0 ? (
        <FlatList
          contentContainerStyle={[s.list, s.grow]}
          data={[]}
          keyExtractor={(_, i) => String(i)}
          renderItem={() => null}
          refreshControl={<RefreshControl refreshing={refreshing} onRefresh={onRefresh} tintColor={v2.brand.red} />}
          ListEmptyComponent={
            <EmptyState
              title="No one blocked"
              body="Users you block from a listing show up here. You can unblock them anytime. Pull down to refresh."
            />
          }
        />
      ) : (
        <FlatList
          contentContainerStyle={s.list}
          data={rows}
          keyExtractor={(r) => r.blocked_id}
          refreshControl={<RefreshControl refreshing={refreshing} onRefresh={onRefresh} tintColor={v2.brand.red} />}
          renderItem={({ item }) => {
            const name = item.blocked?.display_name?.trim() || 'Blocked user';
            return (
              <View style={s.row}>
                <View style={s.rowText}>
                  <Text style={[textStyle('title'), s.name]} numberOfLines={1}>{name}</Text>
                  <Text style={[textStyle('bodySm'), s.meta]}>Blocked {new Date(item.created_at).toLocaleDateString()}</Text>
                </View>
                <Button label="Unblock" variant="secondary" size="sm" onPress={() => handleUnblock(item.blocked_id, name)} />
              </View>
            );
          }}
        />
      )}
    </View>
  );
}

const s = StyleSheet.create({
  root: { flex: 1, backgroundColor: v2.surface.canvas },
  center: { flex: 1, alignItems: 'center', justifyContent: 'center', gap: v2.space.md, padding: v2.space.xl },
  failTitle: { color: v2.text.primary, textAlign: 'center' },
  failBody: { color: v2.text.muted, textAlign: 'center', maxWidth: 320 },
  retry: { minWidth: 160 },

  list: { paddingHorizontal: v2.space.lg, paddingTop: v2.space.sm, paddingBottom: v2.space.xxxl },
  grow: { flexGrow: 1 },
  row: { flexDirection: 'row', alignItems: 'center', gap: v2.space.md, paddingVertical: v2.space.md, borderBottomWidth: 1, borderBottomColor: v2.border.default },
  rowText: { flex: 1, minWidth: 0 },
  name: { color: v2.text.primary },
  meta: { color: v2.text.muted, marginTop: 2 },
});
