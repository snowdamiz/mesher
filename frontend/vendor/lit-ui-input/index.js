// LitUI Input stub - registers <lui-input> custom element
if (typeof window !== 'undefined' && !customElements.get('lui-input')) {
  customElements.define('lui-input', class extends HTMLElement {
    connectedCallback() {
      this.innerHTML = `<input />`
    }
  })
}
