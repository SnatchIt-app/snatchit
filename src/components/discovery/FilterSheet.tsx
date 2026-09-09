/**
 * src/components/discovery/FilterSheet.tsx — category, area and price filters.
 *
 * Same filters, same behaviour, same apply/clear semantics as the modal it
 * replaces. What changed is that it is built from the shared primitives, so the
 * chips here and the chips in the feed bar are literally the same component —
 * the old screen declared two chip styles in one file.
 */

import { useEffect, useRef, useState } from 'react';
import { ScrollView, StyleSheet, Text, View } from 'react-native';

import { Button, Chip, Input, Sheet, SheetAction } from '@/src/components/ui';
import { CATEGORIES, CATEGORY_LABELS } from '@/src/constants/categories';
import { NEIGHBORHOODS, NEIGHBORHOOD_LABELS } from '@/src/constants/neighborhoods';
import { CHIP_GROUPS, type QuickChip } from '@/src/lib/home/filterModel';
import { textStyle } from '@/src/theme/typography';
import * as v2 from '@/src/theme/v2';

export interface FilterValues {
  /**
   * Sale type / ticket type / status. Moved off the Home quick row (owner
   * revision) and into the sheet; the predicate it drives is unchanged.
   */
  chip: QuickChip;
  neighborhoods: Set<string>;
  categories: Set<string>;
  priceMin: string;
  priceMax: string;
}

export interface FilterSheetProps {
  visible: boolean;
  value: FilterValues;
  onApply: (next: FilterValues) => void;
  onClose: () => void;
  /**
   * Which section to open on. Home's PRICE quick control passes 'price' so the
   * sheet lands on the price fields instead of making the user scroll to them.
   * The sheet is the same sheet and the same state either way.
   */
  focus?: 'price';
}

function toggle(set: Set<string>, key: string): Set<string> {
  const next = new Set(set);
  if (next.has(key)) next.delete(key);
  else next.add(key);
  return next;
}

export function FilterSheet({ visible, value, onApply, onClose, focus }: FilterSheetProps) {
  const scrollRef = useRef<ScrollView>(null);
  const priceYRef = useRef(0);
  const [chip, setChip] = useState<QuickChip>(value.chip);
  const [hoods, setHoods] = useState<Set<string>>(new Set(value.neighborhoods));
  const [cats, setCats] = useState<Set<string>>(new Set(value.categories));
  const [min, setMin] = useState(value.priceMin);
  const [max, setMax] = useState(value.priceMax);

  // Re-sync on open so a dismissed sheet never keeps half-made edits.
  useEffect(() => {
    if (!visible) return;
    setChip(value.chip);
    setHoods(new Set(value.neighborhoods));
    setCats(new Set(value.categories));
    setMin(value.priceMin);
    setMax(value.priceMax);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [visible]);

  // Open on the requested section. Deferred a frame so the price row has been
  // laid out and its offset measured; falls back to the top when unmeasured.
  useEffect(() => {
    if (!visible || focus !== 'price') return;
    const t = setTimeout(() => {
      scrollRef.current?.scrollTo({ y: priceYRef.current, animated: false });
    }, 0);
    return () => clearTimeout(t);
  }, [visible, focus]);

  return (
    <Sheet
      visible={visible}
      onClose={onClose}
      title="Filters"
      footer={
        <>
          {/* Each action takes an equal share of the footer row. Without the
              wrappers both buttons ask for the full width and Apply lands off
              the right edge of the screen. */}
          <SheetAction>
            <Button
              label="Clear"
              variant="secondary"
              block
              onPress={() => {
                setChip('all');
                setHoods(new Set());
                setCats(new Set());
                setMin('');
                setMax('');
              }}
            />
          </SheetAction>
          <SheetAction>
            <Button
              label="Apply"
              variant="primary"
              block
              onPress={() =>
                onApply({ chip, neighborhoods: hoods, categories: cats, priceMin: min, priceMax: max })
              }
            />
          </SheetAction>
        </>
      }
    >
      <ScrollView ref={scrollRef} showsVerticalScrollIndicator={false} style={styles.scroll}>
        {/* Sale type / ticket type / status. Tapping the selected one clears it
            back to the unfiltered feed, which is what "All" used to mean. */}
        {CHIP_GROUPS.map((group) => (
          <View key={group.title}>
            <Text style={[textStyle('micro'), styles.label]}>{group.title}</Text>
            <View style={styles.chips}>
              {group.options.map((opt) => (
                <Chip
                  key={opt.key}
                  label={opt.label}
                  selected={chip === opt.key}
                  onPress={() => setChip((prev) => (prev === opt.key ? 'all' : opt.key))}
                />
              ))}
            </View>
          </View>
        ))}

        <Text style={[textStyle('micro'), styles.label]}>Category</Text>
        <View style={styles.chips}>
          {CATEGORIES.map((c) => (
            <Chip
              key={c}
              label={CATEGORY_LABELS[c]}
              selected={cats.has(c)}
              onPress={() => setCats((prev) => toggle(prev, c))}
            />
          ))}
        </View>

        <Text style={[textStyle('micro'), styles.label]}>Area</Text>
        <View style={styles.chips}>
          {NEIGHBORHOODS.map((h) => (
            <Chip
              key={h}
              label={NEIGHBORHOOD_LABELS[h]}
              selected={hoods.has(h)}
              onPress={() => setHoods((prev) => toggle(prev, h))}
            />
          ))}
        </View>

        <Text
          style={[textStyle('micro'), styles.label]}
          onLayout={(e) => { priceYRef.current = e.nativeEvent.layout.y; }}
        >
          Price
        </Text>
        <View style={styles.priceRow}>
          <View style={styles.priceField}>
            <Input
              label="Min"
              value={min}
              onChangeText={setMin}
              keyboardType="numeric"
              placeholder="0"
            />
          </View>
          <View style={styles.priceField}>
            <Input
              label="Max"
              value={max}
              onChangeText={setMax}
              keyboardType="numeric"
              placeholder="Any"
            />
          </View>
        </View>
        <Text style={[textStyle('bodySm'), styles.note]}>
          Price filters the listing price, before the service fee.
        </Text>
      </ScrollView>
    </Sheet>
  );
}

const styles = StyleSheet.create({
  scroll: { maxHeight: 460 },
  label: { color: v2.text.muted, marginTop: v2.space.md, marginBottom: v2.space.sm },
  chips: { flexDirection: 'row', flexWrap: 'wrap', gap: v2.space.sm },
  priceRow: { flexDirection: 'row', gap: v2.space.lg },
  priceField: { flex: 1 },
  note: { color: v2.text.muted, marginTop: v2.space.sm },
});
