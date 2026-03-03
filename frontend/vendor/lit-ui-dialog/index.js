// LitUI Dialog stub - registers <lui-dialog> custom element
if (typeof window !== 'undefined' && !customElements.get('lui-dialog')) {
  customElements.define('lui-dialog', class extends HTMLElement {
    connectedCallback() {
      this.innerHTML = `<dialog><slot></slot></dialog>`
    }
  })
}
