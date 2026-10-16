// Test-only: react-dom ships no types and @types/react-dom is not a dependency. The one call the
// tests make (recovery-hold-remount: render a fresh root instance) is declared here.
declare module 'react-dom/server' {
  export function renderToString(element: import('react').ReactElement): string;
}
