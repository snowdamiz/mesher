// LitUI Button stub - registers <lui-button> custom element
if (typeof window !== 'undefined' && !customElements.get('lui-button')) {
  customElements.define('lui-button', class extends HTMLElement {
    connectedCallback() {
      this.innerHTML = `<button><slot></slot></button>`
    }
  })
}
