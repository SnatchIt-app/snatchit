/**
 * src/components/ErrorBoundary.tsx
 *
 * Catches render errors anywhere in the component tree and shows a
 * friendly fallback screen instead of a white screen / crash.
 */
import * as Sentry from '@sentry/react-native';
import React, { Component, type ErrorInfo, type ReactNode } from 'react';
import { StyleSheet, Text, TouchableOpacity, View } from 'react-native';

type Props  = { children: ReactNode };
type State  = { hasError: boolean; error: Error | null };

export default class ErrorBoundary extends Component<Props, State> {
  state: State = { hasError: false, error: null };

  static getDerivedStateFromError(error: Error): State {
    return { hasError: true, error };
  }

  componentDidCatch(error: Error, info: ErrorInfo) {
    console.error('[ErrorBoundary] Uncaught error:', error, info.componentStack);
    Sentry.captureException(error, {
      contexts: { react: { componentStack: info.componentStack } },
    });
  }

  private handleReset = () => {
    this.setState({ hasError: false, error: null });
  };

  render() {
    if (!this.state.hasError) return this.props.children;

    return (
      <View style={s.container}>
        <Text style={s.emoji}>🚧</Text>
        <Text style={s.title}>Something went wrong</Text>
        <Text style={s.subtitle}>
          The app ran into an unexpected error. Tap below to try again.
        </Text>

        <TouchableOpacity style={s.button} onPress={this.handleReset}>
          <Text style={s.buttonText}>Try Again</Text>
        </TouchableOpacity>

        {/*
          We deliberately do NOT render this.state.error.message in production:
          internal exception text (DB errors, third-party API failures, stack
          fragments) must not leak to end-users. The full error is captured by
          Sentry in componentDidCatch().
        */}
      </View>
    );
  }
}

const s = StyleSheet.create({
  container:  { flex: 1, backgroundColor: '#111', alignItems: 'center', justifyContent: 'center', padding: 32 },
  emoji:      { fontSize: 48, marginBottom: 16 },
  title:      { fontSize: 22, fontWeight: '800', color: '#fff', marginBottom: 8, textAlign: 'center' },
  subtitle:   { fontSize: 14, color: '#999', textAlign: 'center', marginBottom: 24, lineHeight: 20 },
  button:     { backgroundColor: '#E63946', paddingHorizontal: 32, paddingVertical: 14, borderRadius: 12 },
  buttonText: { color: '#fff', fontSize: 16, fontWeight: '700' },
});
