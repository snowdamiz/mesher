/**
 * Streem-2 framework runtime stubs.
 * Replace with real package when available.
 */

export function signal(initial) {
  let _value = initial
  const listeners = new Set()
  return {
    get value() { return _value },
    set value(v) { _value = v; listeners.forEach(fn => fn()) },
  }
}

export function computed(fn) {
  return { get value() { return fn() } }
}

export function effect(fn) {
  fn()
  return () => {}
}

export function render(fn, target) {
  // Stub: in real Streem-2, this mounts the reactive DOM tree
  console.log('[streem stub] render called')
}

export function Show(props) {
  // Stub: conditional rendering component
  return null
}
