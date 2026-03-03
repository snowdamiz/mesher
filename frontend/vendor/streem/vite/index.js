/**
 * Streem-2 Vite plugin stub.
 * In production, this handles JSX transform for Streem-2 reactive DOM.
 */
export default function streem() {
  return {
    name: 'streem-vite-stub',
    config() {
      return {
        esbuild: {
          jsx: 'automatic',
          jsxImportSource: 'streem',
        },
      }
    },
  }
}
