/**
 * Mesher root application component.
 *
 * On mount:
 *   - Check auth via api.auth.me()
 *   - Not logged in: show login page
 *   - Logged in with no orgs: redirect to org-setup (first visit per CONTEXT.md)
 *   - Logged in with orgs: redirect to org settings (subsequent per CONTEXT.md)
 *
 * Routes to appropriate page component based on hash.
 */
import { signal, effect, Show, render } from 'streem'
import { api } from './lib/api'
import { route, navigate } from './lib/router'
import { LoginPage } from './pages/login'
import { RegisterPage } from './pages/register'
import { ResetPage, ResetConfirmPage } from './pages/reset'
import { OrgSetupPage } from './pages/org-setup'
import { OrgSettingsPage } from './pages/org-settings'

function App() {
  const user = signal<{ id: string; email: string } | null>(null)
  const loading = signal(true)
  const currentRoute = route()

  // Check authentication on mount
  async function checkAuth() {
    try {
      const me = await api.auth.me()
      user.value = me

      // Auto-redirect from / or /login based on org membership
      const path = currentRoute.value.path
      if (path === '/' || path === '/login') {
        const orgsRes = await api.orgs.list()
        if (orgsRes.organizations && orgsRes.organizations.length > 0) {
          navigate(`/org/${orgsRes.organizations[0].id}/settings`)
        } else {
          navigate('/org-setup')
        }
      }
    } catch {
      user.value = null
      // If on a protected route, redirect to login
      const path = currentRoute.value.path
      const publicPaths = ['/', '/login', '/register', '/reset', '/reset-confirm']
      if (!publicPaths.includes(path) && !path.startsWith('/invites/')) {
        navigate('/login')
      }
    } finally {
      loading.value = false
    }
  }

  checkAuth()

  async function handleLogout() {
    await api.auth.logout()
    user.value = null
    navigate('/login')
  }

  return (
    <div class="app">
      <Show when={() => loading.value}>
        {() => (
          <div style="display: flex; align-items: center; justify-content: center; height: 100vh; font-size: 16px; color: #6b7280;">
            Loading...
          </div>
        )}
      </Show>

      <Show when={() => !loading.value}>
        {() => (
          <div>
            {/* Header bar for authenticated users */}
            <Show when={() => user.value !== null}>
              {() => (
                <header style="display: flex; justify-content: space-between; align-items: center; padding: 12px 24px; border-bottom: 1px solid #e5e7eb; background: #fff;">
                  <a href="#/" style="font-weight: 700; font-size: 18px; text-decoration: none; color: #111827;">
                    Mesher
                  </a>
                  <div style="display: flex; align-items: center; gap: 16px;">
                    <span style="font-size: 14px; color: #6b7280;">
                      {() => user.value?.email}
                    </span>
                    <lui-button variant="ghost" on:click={handleLogout}>
                      Log out
                    </lui-button>
                  </div>
                </header>
              )}
            </Show>

            {/* Route switch */}
            <Show when={() => currentRoute.value.path === '/login' || currentRoute.value.path === '/'}>
              {() => <LoginPage />}
            </Show>

            <Show when={() => currentRoute.value.path === '/register'}>
              {() => <RegisterPage />}
            </Show>

            <Show when={() => currentRoute.value.path === '/reset'}>
              {() => <ResetPage />}
            </Show>

            <Show when={() => currentRoute.value.path === '/reset-confirm'}>
              {() => <ResetConfirmPage />}
            </Show>

            <Show when={() => currentRoute.value.path === '/org-setup'}>
              {() => <OrgSetupPage />}
            </Show>

            <Show when={() => currentRoute.value.path === '/org/:id/settings'}>
              {() => <OrgSettingsPage orgId={currentRoute.value.params.id} />}
            </Show>
          </div>
        )}
      </Show>
    </div>
  )
}

render(() => <App />, document.getElementById('app')!)
