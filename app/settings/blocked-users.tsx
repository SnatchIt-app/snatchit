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
import {
  ActivityIndicator,
  Alert,
  FlatList,
  Pressable,
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
  const [rows, setRows] = useState<Row[]>([]);
  const [loading, setLoading] = useState(true);

  const fetchRows = useCallback(async () => {
    if (!user) return;
    setLoading(true);
    try {
      const { data, error } = await supabase
        .from('user_blocks')
        .select('blocked_id, created_at, blocked:profiles!user_blocks_blocked_id_fkey(display_name)')
        .eq('blocker_id', user.id)
        .order('created_at', { ascending: false });

      if (error) {
        console.warn('[blocked-users] fetch error:', error.message);
        setRows([]);
        return;
      }
      // PostgREST returns the joined `blocked` as an object OR an array
      // depending on the FK direction inference. Normalize.
      const normalized: Row[] = (data ?? []).map((r: any) => ({
        blocked_id: r.blocked_id,
        created_at: r.created_at,
        blocked:    Array.isArray(r.blocked) ? r.blocked[0] ?? null : (r.blocked ?? null),
      }));
      setRows(normalized);
    } finally {
      setLoading(false);
    }
  }, [user]);

  useEffect(() => { fetchRows(); }, [fetchRows]);

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
            // Local optimistic update; fetchRows would also work.
            setRows(prev => prev.filter(r => r.blocked_id !== blockedId));
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
        <View style={s.center}>
          <Text style={s.emptyTitle}>No one blocked</Text>
          <Text style={s.emptyBody}>
            Users you block from a listing will appear here. You can unblock
            them anytime.
          </Text>
        </View>
      ) : (
        <FlatList
          contentContainerStyle={s.list}
          data={rows}
          keyExtractor={(r) => r.blocked_id}
          ItemSeparatorComponent={() => <View style={s.sep} />}
          renderItem={({ item }) => {
            const name = item.blocked?.display_name?.trim() || 'Snatch It user';
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
