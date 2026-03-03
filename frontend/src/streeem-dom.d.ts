/**
 * Type augmentation for @streeem/dom.
 *
 * ShowProps.children is typed as `Node | Node[] | (() => Node | Node[]) | null | undefined`
 * but JSX.Element is `Node | Node[] | null | undefined`. Arrow functions returning
 * JSX.Element don't satisfy `() => Node | Node[]` because of the undefined possibility.
 * This augmentation widens the children type to accept `(() => JSX.Element)`.
 */
import '@streeem/dom'

declare module '@streeem/dom' {
  export function Show(props: {
    when: boolean | (() => boolean)
    fallback?: Node | Node[] | null
    children: Node | Node[] | (() => Node | Node[] | null | undefined) | null | undefined
  }): DocumentFragment
}
