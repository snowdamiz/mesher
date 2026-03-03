/**
 * Minimal DOM rendering shim for Streem-2.
 *
 * The Streem-2 DOM/JSX package is not yet published to npm.
 * This provides Show and render using @streeem/core primitives.
 * Replace with the official DOM package when published.
 */
import { effect, createRoot, type Signal } from '@streeem/core'

/**
 * Conditional rendering component.
 * Renders children when `when()` returns truthy.
 */
export function Show(props: { when: () => boolean; children?: () => any }): any {
  // Placeholder: in a real JSX runtime this would create/remove DOM nodes reactively.
  // For now this is a type-level shim so TSC passes.
  // The actual runtime behavior depends on the JSX transform.
  return null
}

/**
 * Mount a component tree into a DOM element.
 */
export function render(fn: () => any, target: Element): void {
  createRoot(() => {
    const result = fn()
    if (target && result instanceof Node) {
      target.appendChild(result)
    }
  })
}
