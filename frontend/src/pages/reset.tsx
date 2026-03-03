/**
 * Password reset page.
 *
 * Two states:
 * 1. Request form: email input, sends reset link.
 * 2. Confirm form (when URL has token param): new password input, confirms reset.
 */
import { signal } from '@streeem/core'
import { Show } from '../lib/streem-dom'
import { api } from '../lib/api'
import { navigate, route } from '../lib/router'
import '@lit-ui/input'
import '@lit-ui/button'

export function ResetPage() {
  const email = signal('')
  const error = signal<string | null>(null)
  const success = signal<string | null>(null)
  const loading = signal(false)

  async function handleRequestReset(e: Event) {
    e.preventDefault()
    error.value = null
    success.value = null
    loading.value = true
    try {
      await api.auth.resetPassword(email.value)
      success.value = 'Check your email for a password reset link.'
    } catch (err: any) {
      error.value = err.error || 'Failed to send reset email. Please try again.'
    } finally {
      loading.value = false
    }
  }

  return (
    <div class="reset-page" style="max-width: 400px; margin: 80px auto; padding: 0 16px;">
      <h1 style="text-align: center; margin-bottom: 32px;">Reset Password</h1>

      <form onSubmit={handleRequestReset}>
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

        <Show when={() => error.value !== null}>
          {() => (
            <div style="color: #ef4444; margin-bottom: 16px; font-size: 14px;">
              {() => error.value}
            </div>
          )}
        </Show>

        <Show when={() => success.value !== null}>
          {() => (
            <div style="color: #22c55e; margin-bottom: 16px; font-size: 14px;">
              {() => success.value}
            </div>
          )}
        </Show>

        <lui-button
          variant="primary"
          type="submit"
          style="width: 100%;"
          disabled={() => loading.value}
        >
          {() => loading.value ? 'Sending...' : 'Send Reset Link'}
        </lui-button>

        <div style="text-align: center; margin-top: 16px; font-size: 14px;">
          <a href="#/login" style="color: #3b82f6;">Back to login</a>
        </div>
      </form>
    </div>
  )
}

export function ResetConfirmPage() {
  const newPassword = signal('')
  const error = signal<string | null>(null)
  const loading = signal(false)

  async function handleConfirmReset(e: Event) {
    e.preventDefault()
    error.value = null
    loading.value = true
    const token = route().value.params.token || ''
    if (!token) {
      error.value = 'Invalid or missing reset token.'
      loading.value = false
      return
    }
    try {
      await api.auth.confirmReset(token, newPassword.value)
      // Navigate to login with a success indicator
      navigate('/login')
    } catch (err: any) {
      error.value = err.error || 'Failed to reset password. The link may have expired.'
    } finally {
      loading.value = false
    }
  }

  return (
    <div class="reset-confirm-page" style="max-width: 400px; margin: 80px auto; padding: 0 16px;">
      <h1 style="text-align: center; margin-bottom: 32px;">Set New Password</h1>

      <form onSubmit={handleConfirmReset}>
        <div style="margin-bottom: 16px;">
          <lui-input
            type="password"
            label="New Password"
            required
            value={() => newPassword.value}
            on:input={(e: Event) => { newPassword.value = (e.target as HTMLInputElement).value }}
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
          {() => loading.value ? 'Resetting...' : 'Reset Password'}
        </lui-button>

        <div style="text-align: center; margin-top: 16px; font-size: 14px;">
          <a href="#/login" style="color: #3b82f6;">Back to login</a>
        </div>
      </form>
    </div>
  )
}
