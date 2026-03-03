/**
 * Streem-2 framework type stubs.
 * Based on research: signals, computed, effect, Show, render.
 */

export interface Signal<T> {
  value: T
}

export function signal<T>(initial: T): Signal<T>
export function computed<T>(fn: () => T): Signal<T>
export function effect(fn: () => void | (() => void)): () => void
export function render(fn: () => any, target: Element): void

export function Show(props: { when: () => boolean; children?: () => any }): any

declare global {
  namespace JSX {
    interface IntrinsicElements {
      [elemName: string]: any
    }
    interface Element {}
    interface ElementClass {}
    interface ElementAttributesProperty { props: {} }
    interface ElementChildrenAttribute { children: {} }
  }
}
