export function jsx(type: any, props: any, key?: string): any
export function jsxs(type: any, props: any, key?: string): any
export function Fragment(props: { children?: any }): any
export namespace JSX {
  interface IntrinsicElements {
    [elemName: string]: any
  }
  interface Element {}
}
