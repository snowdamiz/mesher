// LitUI Toast stub - registers <lui-toast> custom element
if (typeof window !== 'undefined' && !customElements.get('lui-toast')) {
  customElements.define('lui-toast', class extends HTMLElement {
    connectedCallback() {
      this.innerHTML = `<div><slot></slot></div>`
    }
  })
}
