// LitUI Tabs stub - registers <lui-tabs> and <lui-tab> custom elements
if (typeof window !== 'undefined' && !customElements.get('lui-tabs')) {
  customElements.define('lui-tabs', class extends HTMLElement {
    connectedCallback() {
      this.innerHTML = `<div role="tablist"><slot></slot></div>`
    }
  })
}
if (typeof window !== 'undefined' && !customElements.get('lui-tab')) {
  customElements.define('lui-tab', class extends HTMLElement {
    connectedCallback() {
      this.innerHTML = `<div role="tabpanel"><slot></slot></div>`
    }
  })
}
