/**
 * Login page.
 *
 * OSS tier: Email + password form.
 * SaaS tier: Single Google sign-in button (no email/password form).
 *
 * Per CONTEXT.md locked decisions:
 *   - SaaS: Google OAuth only
 *   - OSS: Email + password only
 */
import { signal } from '@streeem/core'
import { Show } from '@streeem/dom'
import { api } from '../lib/api'
import { navigate } from '../lib/router'
import '@lit-ui/input'
import '@lit-ui/button'

export function LoginPage() {
  const email = signal('')
  const password = signal('')
  const error = signal<string | null>(null)
  const loading = signal(false)
  const tier = signal<string>('oss')

  // Detect tier from backend config endpoint.
  // Falls back to 'oss' if the endpoint is unavailable.
  api.config.tier()
    .then((res) => { tier.value = res.tier })
    .catch(() => { tier.value = 'oss' })

  async function handleOSSLogin(e: Event) {
    e.preventDefault()
    error.value = null
    loading.value = true
    try {
      await api.auth.login(email.value, password.value)
      // Check if user has orgs to determine redirect target
      const orgsRes = await api.orgs.list()
      if (orgsRes.organizations && orgsRes.organizations.length > 0) {
        navigate(`/org/${orgsRes.organizations[0].id}/settings`)
      } else {
        navigate('/org-setup')
      }
    } catch (err: any) {
      if (err.status === 401) {
        error.value = 'Invalid email or password'
      } else {
        error.value = err.error || 'Login failed. Please try again.'
      }
    } finally {
      loading.value = false
    }
  }

  function handleGoogleLogin() {
    window.location.href = '/api/auth/oauth/google'
  }

  return (
    <div class="login-page" style="max-width: 400px; margin: 80px auto; padding: 0 16px;">
      <h1 style="text-align: center; margin-bottom: 32px;">Sign in to Mesher</h1>

      <Show when={() => tier.value === 'saas'}>
        {() => (
          <div style="text-align: center;">
            <lui-button
              variant="primary"
              style="width: 100%;"
              on:click={handleGoogleLogin}
            >
              Sign in with Google
            </lui-button>
          </div>
        )}
      </Show>

      <Show when={() => tier.value === 'oss'}>
        {() => (
          <form onSubmit={handleOSSLogin}>
            <div style="margin-bottom: 16px;">
              <lui-input
                type="email"
                label="Email"
                placeholder="you@example.com"
                required
                value={() => email.value}
                on:input={(e: Event) => { email.value = (e.target as HTMLInputElement).value }}
              />
            </div>

            <div style="margin-bottom: 16px;">
              <lui-input
                type="password"
                label="Password"
                required
                value={() => password.value}
                on:input={(e: Event) => { password.value = (e.target as HTMLInputElement).value }}
              />
            </div>

            <Show when={() => error.value !== null}>
              {() => (
                <div style="color: #ef4444; margin-bottom: 16px; font-size: 14px;">
                  {() => error.value}
                </div>
              )}
            </Show>

            <lui-button
              variant="primary"
              type="submit"
              style="width: 100%;"
              disabled={() => loading.value}
            >
              {() => loading.value ? 'Signing in...' : 'Sign In'}
            </lui-button>

            <div style="text-align: center; margin-top: 16px; font-size: 14px;">
              <a href="#/register" style="color: #3b82f6;">Create an account</a>
              <span style="margin: 0 8px; color: #9ca3af;">|</span>
              <a href="#/reset" style="color: #3b82f6;">Forgot password?</a>
            </div>
          </form>
        )}
      </Show>
    </div>
  )
}
