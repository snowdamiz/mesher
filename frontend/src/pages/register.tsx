/**
 * Registration page (OSS only).
 *
 * Per CONTEXT.md: email + password only (no name field).
 * On success: navigate to org setup wizard.
 */
import { signal, Show } from 'streem'
import { api } from '../lib/api'
import { navigate } from '../lib/router'
import '@lit-ui/input'
import '@lit-ui/button'

export function RegisterPage() {
  const email = signal('')
  const password = signal('')
  const error = signal<string | null>(null)
  const loading = signal(false)

  async function handleRegister(e: Event) {
    e.preventDefault()
    error.value = null
    loading.value = true
    try {
      await api.auth.register(email.value, password.value)
      navigate('/org-setup')
    } catch (err: any) {
      if (err.status === 409) {
        error.value = 'An account with this email already exists'
      } else {
        error.value = err.error || 'Registration failed. Please try again.'
      }
    } finally {
      loading.value = false
    }
  }

  return (
    <div class="register-page" style="max-width: 400px; margin: 80px auto; padding: 0 16px;">
      <h1 style="text-align: center; margin-bottom: 32px;">Create Account</h1>

      <form onSubmit={handleRegister}>
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
          {() => loading.value ? 'Creating Account...' : 'Create Account'}
        </lui-button>

        <div style="text-align: center; margin-top: 16px; font-size: 14px;">
          <span style="color: #6b7280;">Already have an account?</span>{' '}
          <a href="#/login" style="color: #3b82f6;">Sign in</a>
        </div>
      </form>
    </div>
  )
}
