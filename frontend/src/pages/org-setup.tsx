/**
 * Organization setup wizard.
 *
 * Per CONTEXT.md: Post-login landing is org setup wizard on first visit.
 * Simple single-step wizard: enter org name -> create -> redirect to settings.
 */
import { signal } from '@streeem/core'
import { Show } from '@streeem/dom'
import { api } from '../lib/api'
import { navigate } from '../lib/router'
import '@lit-ui/input'
import '@lit-ui/button'

export function OrgSetupPage() {
  const orgName = signal('')
  const error = signal<string | null>(null)
  const loading = signal(false)

  async function handleCreateOrg(e: Event) {
    e.preventDefault()
    error.value = null
    loading.value = true
    try {
      const org = await api.orgs.create(orgName.value)
      navigate(`/org/${org.id}/settings`)
    } catch (err: any) {
      error.value = err.error || 'Failed to create organization. Please try again.'
    } finally {
      loading.value = false
    }
  }

  return (
    <div class="org-setup-page" style="max-width: 500px; margin: 80px auto; padding: 0 16px;">
      <h1 style="text-align: center; margin-bottom: 8px;">Create your organization</h1>
      <p style="text-align: center; color: #6b7280; margin-bottom: 32px;">
        Organizations group your projects, team members, and API keys.
      </p>

      <form onSubmit={handleCreateOrg}>
        <div style="margin-bottom: 16px;">
          <lui-input
            label="Organization name"
            placeholder="My Company"
            required
            value={() => orgName.value}
            on:input={(e: Event) => { orgName.value = (e.target as HTMLInputElement).value }}
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
          {() => loading.value ? 'Creating...' : 'Create Organization'}
        </lui-button>
      </form>
    </div>
  )
}
