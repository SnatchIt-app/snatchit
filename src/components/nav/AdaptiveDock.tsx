/**
 * src/components/nav/AdaptiveDock.tsx — Snatch It's floating glass navigation dock.
 *
 * Replaces the default tab bar (routing preserved — this is the `tabBar` render
 * prop). A rounded, dark-translucent, iOS-native floating pill that sits well
 * above the bottom edge. The ACTIVE destination gets its own lighter inner capsule
 * (never a red frame, never a web-tab underline); inactive icons are muted.
 *
 * COLLAPSE is GLOBAL across the scrollable primary tabs (Home, Create, Bids,
 * Profile): a spatial CONTRACTION toward the LEFT anchor — the pill narrows while
 * the secondary icons fade and the active icon slides to the left, so the dock
 * visibly shrinks into the active control at bottom-left (never the centre). Each
 * tab feeds its own scroll state; one behavioural source of truth. The compact
 * control shows the ACTIVE tab's icon and, tapped, only re-expands. Motion is fast
 * (220ms) and instant under reduce-motion.
 *
 * KEYBOARD: while a text keyboard occupies the bottom, the dock drops out of the
 * way (and stops intercepting touches), then restores on dismiss — so it never
 * floats over a focused form.
 *
 * Tickets is now the fifth destination (Phase 11): `navItems({ tickets: true })`
 * returns the approved Home · Create · Bids · Tickets · Profile order. No dock
 * geometry, glass, animation, threshold, capsule, or safe-area rule changed — the
 * layout was always built for five items; only the data set was flipped. Material
 * note: true frosted BlurView needs expo-blur (not installed, deliberately not
 * added); the dark translucent surface is the closest premium approximation.
 */

import { useEffect, useMemo, useRef, useState } from 'react';
import { AccessibilityInfo, Animated, Keyboard, Platform, Pressable, StyleSheet, View, useWindowDimensions } from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import * as Haptics from 'expo-haptics';
import type { BottomTabBarProps } from '@react-navigation/bottom-tabs';

import { IconSymbol } from '@/components/ui/icon-symbol';
import { useDockCollapsed, useDockExpander } from '@/src/components/nav/dockContext';
import { navItems, isCollapsingRoute } from '@/src/lib/nav/navItems';
import { DOCK_GAP, DOCK_HEIGHT, DOCK_RADIUS, DOCK_SIDE_MARGIN } from '@/src/lib/nav/navInsets';
import * as v2 from '@/src/theme/v2';

const ITEMS = navItems({ tickets: true }); // Home, Create, Bids, Tickets, Profile
const ITEM_W = 66;
const PAD = 8;
const FULL_W = ITEMS.length * ITEM_W + PAD * 2;   // derived — supports 4 or 5 items
const COMPACT_W = ITEM_W + PAD * 2;               // derived — same object, collapsed
const ICON = 27;
const ICON_ACTIVE = 28;
const DURATION = 220;

export function AdaptiveDock({ state, navigation }: BottomTabBarProps) {
  const insets = useSafeAreaInsets();
  const { width: screenW } = useWindowDimensions();
  const expandRoute = useDockExpander();

  const activeRoute = state.routes[state.index]?.name;
  const collapsedFlag = useDockCollapsed(activeRoute);
  const activeIndex = Math.max(0, ITEMS.findIndex((i) => i.route === activeRoute));
  const collapsing = isCollapsingRoute(activeRoute) && collapsedFlag;

  // 0 = full pill, 1 = compact. Reduce-motion → instant.
  const anim = useRef(new Animated.Value(0)).current;
  const reduceMotion = useRef(false);
  useEffect(() => {
    let active = true;
    AccessibilityInfo.isReduceMotionEnabled().then((v) => { if (active) reduceMotion.current = v; });
    const sub = AccessibilityInfo.addEventListener('reduceMotionChanged', (v) => { reduceMotion.current = v; });
    return () => { active = false; sub.remove(); };
  }, []);

  useEffect(() => {
    Animated.timing(anim, {
      toValue: collapsing ? 1 : 0,
      duration: reduceMotion.current ? 0 : DURATION,
      useNativeDriver: false, // width contraction is a layout property
    }).start();
  }, [collapsing, anim]);

  // Switching tabs always arrives expanded.
  useEffect(() => { if (activeRoute) expandRoute(activeRoute); }, [activeRoute, expandRoute]);

  // Keyboard: drop the dock while a text keyboard occupies the bottom.
  const [keyboardUp, setKeyboardUp] = useState(false);
  const kbd = useRef(new Animated.Value(0)).current;
  useEffect(() => {
    const showEvt = Platform.OS === 'ios' ? 'keyboardWillShow' : 'keyboardDidShow';
    const hideEvt = Platform.OS === 'ios' ? 'keyboardWillHide' : 'keyboardDidHide';
    const onShow = Keyboard.addListener(showEvt, () => {
      setKeyboardUp(true);
      Animated.timing(kbd, { toValue: 1, duration: reduceMotion.current ? 0 : 160, useNativeDriver: true }).start();
    });
    const onHide = Keyboard.addListener(hideEvt, () => {
      Animated.timing(kbd, { toValue: 0, duration: reduceMotion.current ? 0 : 160, useNativeDriver: true }).start(() => setKeyboardUp(false));
    });
    return () => { onShow.remove(); onHide.remove(); };
  }, [kbd]);

  // Expanded: centred pill. Collapsed: left anchor. We pin at the left anchor and
  // translate right to centre when expanded, so contraction finishes bottom-left.
  const centeredLeft = Math.max(DOCK_SIDE_MARGIN, (screenW - FULL_W) / 2);
  const containerStyle = useMemo(() => ({
    width: anim.interpolate({ inputRange: [0, 1], outputRange: [FULL_W, COMPACT_W] }),
    transform: [
      { translateX: anim.interpolate({ inputRange: [0, 1], outputRange: [centeredLeft - DOCK_SIDE_MARGIN, 0] }) },
    ],
  }), [anim, centeredLeft]);

  const rowTranslate = anim.interpolate({ inputRange: [0, 1], outputRange: [0, -(activeIndex * ITEM_W)] });
  const secondaryOpacity = anim.interpolate({ inputRange: [0, 1], outputRange: [1, 0] });

  // Keyboard drop (native-driver transform + opacity on the wrapper).
  const kbdStyle = {
    opacity: kbd.interpolate({ inputRange: [0, 1], outputRange: [1, 0] }),
    transform: [{ translateY: kbd.interpolate({ inputRange: [0, 1], outputRange: [0, DOCK_HEIGHT + DOCK_GAP + 24] }) }],
  };

  function onPress(routeKey: string, routeName: string, isFocused: boolean) {
    Haptics.selectionAsync().catch(() => {});
    const event = navigation.emit({ type: 'tabPress', target: routeKey, canPreventDefault: true });
    if (!isFocused && !event.defaultPrevented) navigation.navigate(routeName);
  }

  const activeLabel = ITEMS[activeIndex]?.label ?? 'Navigation';

  return (
    <Animated.View
      style={[styles.wrap, { height: insets.bottom + DOCK_GAP + DOCK_HEIGHT }, kbdStyle]}
      pointerEvents={keyboardUp ? 'none' : 'box-none'}
    >
      {/* The dock's REAL bottom anchor. An absolute child ignores the wrapper's
          padding, so the lift lives here, on the dock itself. */}
      <Animated.View style={[styles.dock, { left: DOCK_SIDE_MARGIN, bottom: insets.bottom + DOCK_GAP }, containerStyle]}>
        <Animated.View style={[styles.row, { width: FULL_W, transform: [{ translateX: rowTranslate }] }]}>
          {ITEMS.map((item) => {
            const routeIndex = state.routes.findIndex((r) => r.name === item.route);
            if (routeIndex < 0) return null;
            const route = state.routes[routeIndex];
            const isFocused = state.index === routeIndex;
            return (
              <Pressable
                key={item.key}
                onPress={() => onPress(route.key, route.name, isFocused)}
                style={styles.item}
                accessibilityRole="tab"
                accessibilityLabel={item.label}
                accessibilityState={{ selected: isFocused }}
                hitSlop={6}
              >
                {/* Selected inner capsule — the active-state treatment (never a red frame). */}
                {isFocused ? <View style={styles.selected} /> : null}
                <Animated.View style={isFocused ? undefined : { opacity: secondaryOpacity }}>
                  <IconSymbol name={item.icon as never} size={isFocused ? ICON_ACTIVE : ICON} color={isFocused ? v2.text.primary : v2.text.muted} />
                </Animated.View>
              </Pressable>
            );
          })}
        </Animated.View>

        {/* When collapsed, the whole compact pill is a tap target that re-expands. */}
        <Pressable
          style={StyleSheet.absoluteFill}
          pointerEvents={collapsing ? 'auto' : 'none'}
          onPress={() => activeRoute && expandRoute(activeRoute)}
          accessibilityRole="button"
          accessibilityLabel={`Show navigation. ${activeLabel} selected.`}
        />
      </Animated.View>
    </Animated.View>
  );
}

const styles = StyleSheet.create({
  wrap: {
    position: 'absolute',
    left: 0,
    right: 0,
    bottom: 0,
    // height is applied inline from the live safe-area inset so the wrapper spans
    // exactly up to the dock's top (keeps the dock's touch area inside a box-none
    // parent).
  },
  dock: {
    position: 'absolute',
    // bottom is applied inline (insets.bottom + DOCK_GAP) — the real lift.
    height: DOCK_HEIGHT,
    borderRadius: DOCK_RADIUS,
    // Dark translucent "glass" material. No red frame; a whisper of a neutral
    // hairline gives depth against the black canvas.
    backgroundColor: 'rgba(18,18,20,0.72)',
    borderWidth: StyleSheet.hairlineWidth,
    borderColor: 'rgba(255,255,255,0.10)',
    overflow: 'hidden',
    paddingHorizontal: PAD,
    justifyContent: 'center',
  },
  row: { flexDirection: 'row', height: DOCK_HEIGHT, alignItems: 'center' },
  item: { width: ITEM_W, height: DOCK_HEIGHT, alignItems: 'center', justifyContent: 'center' },
  // The lighter inner region that marks the active destination — proportional to
  // the larger dock so it still sits cleanly inside.
  selected: {
    ...StyleSheet.absoluteFillObject,
    marginVertical: 8,
    marginHorizontal: 9,
    borderRadius: DOCK_RADIUS - 9, // 24
    backgroundColor: 'rgba(255,255,255,0.12)',
  },
});
