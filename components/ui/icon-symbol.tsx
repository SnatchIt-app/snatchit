// Fallback for using MaterialIcons on Android and web.

import MaterialIcons from '@expo/vector-icons/MaterialIcons';
import { SymbolWeight, SymbolViewProps } from 'expo-symbols';
import { ComponentProps } from 'react';
import { OpaqueColorValue, type StyleProp, type TextStyle } from 'react-native';

type IconMapping = Record<SymbolViewProps['name'], ComponentProps<typeof MaterialIcons>['name']>;
type IconSymbolName = keyof typeof MAPPING;

/**
 * Add your SF Symbols to Material Icons mappings here.
 * - see Material Icons in the [Icons Directory](https://icons.expo.fyi).
 * - see SF Symbols in the [SF Symbols](https://developer.apple.com/sf-symbols/) app.
 */
const MAPPING = {
  'house.fill': 'home',
  'plus.circle.fill': 'add-circle',
  'tag.fill': 'local-offer',
  // Reserved for the future Tickets destination (ownership, not scanning).
  'ticket.fill': 'confirmation-number',
  'person.fill': 'person',
  // Media / file upload controls.
  'photo': 'image',
  'doc.text': 'description',
  'checkmark.circle.fill': 'check-circle',
  'plus': 'add',
  'xmark': 'close',
  'paperplane.fill': 'send',
  'chevron.left.forwardslash.chevron.right': 'code',
  'chevron.right': 'chevron-right',
  // State views (offline / server error / no match).
  'wifi.slash': 'wifi-off',
  'exclamationmark.triangle': 'warning',
  'magnifyingglass': 'search',
  /*
   * Chrome controls (IconButton). These replace text CHARACTERS that were rendering in an
   * unpredictable face: B measured the bundled Inter and Oswald cmaps and found the marks the
   * control used — the hamburger, the magnifier, the multiplication sign and the midline ellipsis —
   * absent from both, so iOS was substituting some fallback font for all four. Their weight, size
   * and vertical alignment were therefore outside our control.
   *
   * `line.3.horizontal.decrease` is the filter mark specifically: three lines of decreasing length.
   * The control used to draw a hamburger, which means MENU in an interface (and IDENTICAL TO in
   * mathematics) — never "filters". Material's `filter-list` is the same shape.
   */
  'chevron.left': 'chevron-left',
  'ellipsis': 'more-horiz',
  'line.3.horizontal.decrease': 'filter-list',
} as IconMapping;

/**
 * An icon component that uses native SF Symbols on iOS, and Material Icons on Android and web.
 * This ensures a consistent look across platforms, and optimal resource usage.
 * Icon `name`s are based on SF Symbols and require manual mapping to Material Icons.
 */
export function IconSymbol({
  name,
  size = 24,
  color,
  style,
}: {
  name: IconSymbolName;
  size?: number;
  color: string | OpaqueColorValue;
  style?: StyleProp<TextStyle>;
  weight?: SymbolWeight;
}) {
  return <MaterialIcons color={color} size={size} name={MAPPING[name]} style={style} />;
}
