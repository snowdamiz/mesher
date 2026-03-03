/**
 * Simple hash-based router using Streem-2 signals.
 *
 * Routes:
 *   /login, /register, /reset, /reset-confirm,
 *   /org-setup, /org/:id/settings, /invites/:token
 */
import { signal, effect } from 'streem'

export interface RouteMatch {
  path: string
  params: Record<string, string>
}

const currentRoute = signal<RouteMatch>({ path: '/', params: {} })

function parseHash(): RouteMatch {
  const hash = window.location.hash.slice(1) || '/'
  const clean = hash.startsWith('/') ? hash : `/${hash}`

  // Match /org/:id/settings
  const orgSettingsMatch = clean.match(/^\/org\/([^/]+)\/settings$/)
  if (orgSettingsMatch) {
    return { path: '/org/:id/settings', params: { id: orgSettingsMatch[1] } }
  }

  // Match /invites/:token
  const inviteMatch = clean.match(/^\/invites\/([^/]+)$/)
  if (inviteMatch) {
    return { path: '/invites/:token', params: { token: inviteMatch[1] } }
  }

  // Match /reset-confirm?token=...
  if (clean.startsWith('/reset-confirm')) {
    const urlParams = new URLSearchParams(clean.split('?')[1] || '')
    const token = urlParams.get('token') || ''
    return { path: '/reset-confirm', params: { token } }
  }

  return { path: clean.split('?')[0], params: {} }
}

function onHashChange() {
  currentRoute.value = parseHash()
}

// Initialize on first import
if (typeof window !== 'undefined') {
  window.addEventListener('hashchange', onHashChange)
  currentRoute.value = parseHash()
}

export function navigate(path: string) {
  window.location.hash = path
}

export function route() {
  return currentRoute
}
