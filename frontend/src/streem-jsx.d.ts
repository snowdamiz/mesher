/**
 * JSX type declarations for Streem-2.
 *
 * The Streem-2 DOM/JSX package is not yet published to npm.
 * This provides JSX namespace types so TypeScript can compile .tsx files.
 * Replace with the official Streem-2 DOM package types when published.
 */
declare namespace JSX {
  interface IntrinsicElements {
    [elemName: string]: any
  }
  interface Element {}
  interface ElementClass {}
  interface ElementAttributesProperty { props: {} }
  interface ElementChildrenAttribute { children: {} }
}
