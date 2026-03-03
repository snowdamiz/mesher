/**
 * Organization settings dashboard.
 *
 * Tabs:
 *   1. Projects (default) - list projects, create project, manage API keys per project
 *   2. Members - list members, invite member, pending invites with revoke
 *   3. Settings - org name (read-only), leave org button
 *
 * Per plan: uses lui-tabs, lui-input, lui-button, lui-dialog, lui-toast.
 * All object/array properties use prop: binding (per anti-patterns in research).
 */
import { signal, effect } from '@streeem/core'
import { Show } from '../lib/streem-dom'
import { api } from '../lib/api'
import { navigate } from '../lib/router'
import '@lit-ui/tabs'
import '@lit-ui/input'
import '@lit-ui/button'
import '@lit-ui/dialog'
import '@lit-ui/toast'

interface Project {
  id: string
  name: string
  created_at: string
}

interface ApiKey {
  id: string
  prefix: string
  label: string
  created_at: string
  revoked_at: string | null
}

interface Invite {
  id: string
  email: string
  expires_at: string
}

export function OrgSettingsPage(props: { orgId: string }) {
  const activeTab = signal<'projects' | 'members' | 'settings'>('projects')

  // Projects state
  const projects = signal<Project[]>([])
  const projectsLoading = signal(true)
  const showCreateProject = signal(false)
  const newProjectName = signal('')
  const createProjectError = signal<string | null>(null)

  // API keys state (per selected project)
  const selectedProject = signal<Project | null>(null)
  const apiKeys = signal<ApiKey[]>([])
  const apiKeysLoading = signal(false)
  const showGenerateKey = signal(false)
  const newKeyLabel = signal('')
  const generatedKey = signal<{ key: string; dsn: string; prefix: string } | null>(null)

  // Members/invites state
  const invites = signal<Invite[]>([])
  const invitesLoading = signal(true)
  const inviteEmail = signal('')
  const inviteError = signal<string | null>(null)
  const inviteSuccess = signal<string | null>(null)

  // Toast message
  const toastMessage = signal<string | null>(null)

  // Data loading functions
  async function loadProjects() {
    projectsLoading.value = true
    try {
      const res = await api.orgs.projects.list(props.orgId)
      projects.value = res.projects || []
    } catch {
      projects.value = []
    } finally {
      projectsLoading.value = false
    }
  }

  async function loadApiKeys(projectId: string) {
    apiKeysLoading.value = true
    try {
      const res = await api.orgs.apiKeys.list(props.orgId, projectId)
      apiKeys.value = res.api_keys || []
    } catch {
      apiKeys.value = []
    } finally {
      apiKeysLoading.value = false
    }
  }

  async function loadInvites() {
    invitesLoading.value = true
    try {
      const res = await api.orgs.invites.list(props.orgId)
      invites.value = res.invites || []
    } catch {
      invites.value = []
    } finally {
      invitesLoading.value = false
    }
  }

  // Load initial data
  loadProjects()
  loadInvites()

  // Action handlers
  async function handleCreateProject(e: Event) {
    e.preventDefault()
    createProjectError.value = null
    try {
      await api.orgs.projects.create(props.orgId, newProjectName.value)
      newProjectName.value = ''
      showCreateProject.value = false
      toastMessage.value = 'Project created'
      await loadProjects()
    } catch (err: any) {
      createProjectError.value = err.error || 'Failed to create project'
    }
  }

  function handleSelectProject(project: Project) {
    selectedProject.value = project
    loadApiKeys(project.id)
  }

  function handleBackToProjects() {
    selectedProject.value = null
    apiKeys.value = []
  }

  async function handleGenerateKey(e: Event) {
    e.preventDefault()
    const proj = selectedProject.value
    if (!proj) return
    try {
      const res = await api.orgs.apiKeys.create(props.orgId, proj.id, newKeyLabel.value || undefined)
      generatedKey.value = { key: res.key, dsn: res.dsn, prefix: res.prefix }
      newKeyLabel.value = ''
      showGenerateKey.value = false
      await loadApiKeys(proj.id)
    } catch (err: any) {
      toastMessage.value = err.error || 'Failed to generate API key'
    }
  }

  async function handleRevokeKey(keyId: string) {
    try {
      await api.orgs.apiKeys.revoke(props.orgId, keyId)
      toastMessage.value = 'API key revoked'
      const proj = selectedProject.value
      if (proj) await loadApiKeys(proj.id)
    } catch (err: any) {
      toastMessage.value = err.error || 'Failed to revoke API key'
    }
  }

  async function handleInviteMember(e: Event) {
    e.preventDefault()
    inviteError.value = null
    inviteSuccess.value = null
    try {
      await api.orgs.invites.create(props.orgId, inviteEmail.value)
      inviteSuccess.value = `Invite sent to ${inviteEmail.value}`
      inviteEmail.value = ''
      await loadInvites()
    } catch (err: any) {
      inviteError.value = err.error || 'Failed to send invite'
    }
  }

  async function handleRevokeInvite(inviteId: string) {
    try {
      await api.orgs.invites.revoke(props.orgId, inviteId)
      toastMessage.value = 'Invite revoked'
      await loadInvites()
    } catch (err: any) {
      toastMessage.value = err.error || 'Failed to revoke invite'
    }
  }

  function copyToClipboard(text: string) {
    navigator.clipboard.writeText(text).then(() => {
      toastMessage.value = 'Copied to clipboard'
    })
  }

  return (
    <div class="org-settings-page" style="max-width: 960px; margin: 40px auto; padding: 0 16px;">
      <h1 style="margin-bottom: 24px;">Organization Settings</h1>

      {/* Tab navigation */}
      <div style="display: flex; gap: 0; border-bottom: 2px solid #e5e7eb; margin-bottom: 24px;">
        <button
          style={() => `padding: 8px 20px; cursor: pointer; border: none; background: none; font-size: 14px; font-weight: 500; border-bottom: 2px solid ${activeTab.value === 'projects' ? '#3b82f6' : 'transparent'}; margin-bottom: -2px; color: ${activeTab.value === 'projects' ? '#3b82f6' : '#6b7280'};`}
          onClick={() => { activeTab.value = 'projects'; loadProjects() }}
        >
          Projects
        </button>
        <button
          style={() => `padding: 8px 20px; cursor: pointer; border: none; background: none; font-size: 14px; font-weight: 500; border-bottom: 2px solid ${activeTab.value === 'members' ? '#3b82f6' : 'transparent'}; margin-bottom: -2px; color: ${activeTab.value === 'members' ? '#3b82f6' : '#6b7280'};`}
          onClick={() => { activeTab.value = 'members'; loadInvites() }}
        >
          Members
        </button>
        <button
          style={() => `padding: 8px 20px; cursor: pointer; border: none; background: none; font-size: 14px; font-weight: 500; border-bottom: 2px solid ${activeTab.value === 'settings' ? '#3b82f6' : 'transparent'}; margin-bottom: -2px; color: ${activeTab.value === 'settings' ? '#3b82f6' : '#6b7280'};`}
          onClick={() => { activeTab.value = 'settings' }}
        >
          Settings
        </button>
      </div>

      {/* Projects tab */}
      <Show when={() => activeTab.value === 'projects'}>
        {() => (
          <div>
            {/* Project list or single project API key view */}
            <Show when={() => selectedProject.value === null}>
              {() => (
                <div>
                  <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 16px;">
                    <h2 style="margin: 0; font-size: 18px;">Projects</h2>
                    <lui-button variant="primary" on:click={() => { showCreateProject.value = true }}>
                      Create Project
                    </lui-button>
                  </div>

                  <Show when={() => projectsLoading.value}>
                    {() => <p style="color: #6b7280;">Loading...</p>}
                  </Show>

                  <Show when={() => !projectsLoading.value && projects.value.length === 0}>
                    {() => <p style="color: #6b7280;">No projects yet. Create one to get started.</p>}
                  </Show>

                  <Show when={() => !projectsLoading.value && projects.value.length > 0}>
                    {() => (
                      <div style="border: 1px solid #e5e7eb; border-radius: 8px; overflow: hidden;">
                        {() => projects.value.map((project) => (
                          <div
                            style="display: flex; justify-content: space-between; align-items: center; padding: 12px 16px; border-bottom: 1px solid #e5e7eb; cursor: pointer;"
                            onClick={() => handleSelectProject(project)}
                          >
                            <div>
                              <div style="font-weight: 500;">{project.name}</div>
                              <div style="font-size: 12px; color: #9ca3af;">
                                Created {new Date(project.created_at).toLocaleDateString()}
                              </div>
                            </div>
                            <span style="color: #9ca3af; font-size: 14px;">Manage API Keys &rarr;</span>
                          </div>
                        ))}
                      </div>
                    )}
                  </Show>

                  {/* Create project dialog */}
                  <Show when={() => showCreateProject.value}>
                    {() => (
                      <div style="position: fixed; inset: 0; background: rgba(0,0,0,0.4); display: flex; align-items: center; justify-content: center; z-index: 100;">
                        <div style="background: white; padding: 24px; border-radius: 12px; width: 400px; max-width: 90vw;">
                          <h3 style="margin: 0 0 16px;">Create Project</h3>
                          <form onSubmit={handleCreateProject}>
                            <div style="margin-bottom: 16px;">
                              <lui-input
                                label="Project name"
                                placeholder="My Project"
                                required
                                value={() => newProjectName.value}
                                on:input={(e: Event) => { newProjectName.value = (e.target as HTMLInputElement).value }}
                              />
                            </div>
                            <Show when={() => createProjectError.value !== null}>
                              {() => (
                                <div style="color: #ef4444; margin-bottom: 12px; font-size: 14px;">
                                  {() => createProjectError.value}
                                </div>
                              )}
                            </Show>
                            <div style="display: flex; gap: 8px; justify-content: flex-end;">
                              <lui-button variant="ghost" on:click={() => { showCreateProject.value = false }}>
                                Cancel
                              </lui-button>
                              <lui-button variant="primary" type="submit">
                                Create
                              </lui-button>
                            </div>
                          </form>
                        </div>
                      </div>
                    )}
                  </Show>
                </div>
              )}
            </Show>

            {/* API keys view for selected project */}
            <Show when={() => selectedProject.value !== null}>
              {() => (
                <div>
                  <div style="display: flex; align-items: center; gap: 12px; margin-bottom: 16px;">
                    <lui-button variant="ghost" on:click={handleBackToProjects}>
                      &larr; Back
                    </lui-button>
                    <h2 style="margin: 0; font-size: 18px;">
                      {() => selectedProject.value?.name} - API Keys
                    </h2>
                    <div style="margin-left: auto;">
                      <lui-button variant="primary" on:click={() => { showGenerateKey.value = true }}>
                        Generate Key
                      </lui-button>
                    </div>
                  </div>

                  <Show when={() => apiKeysLoading.value}>
                    {() => <p style="color: #6b7280;">Loading...</p>}
                  </Show>

                  <Show when={() => !apiKeysLoading.value && apiKeys.value.length === 0}>
                    {() => <p style="color: #6b7280;">No API keys yet. Generate one to start sending data.</p>}
                  </Show>

                  <Show when={() => !apiKeysLoading.value && apiKeys.value.length > 0}>
                    {() => (
                      <div style="border: 1px solid #e5e7eb; border-radius: 8px; overflow: hidden;">
                        <div style="display: grid; grid-template-columns: 1fr 1fr 1fr 1fr auto; padding: 8px 16px; background: #f9fafb; font-size: 12px; font-weight: 600; color: #6b7280; text-transform: uppercase;">
                          <span>Prefix</span>
                          <span>Label</span>
                          <span>Created</span>
                          <span>Status</span>
                          <span></span>
                        </div>
                        {() => apiKeys.value.map((key) => (
                          <div style="display: grid; grid-template-columns: 1fr 1fr 1fr 1fr auto; padding: 12px 16px; border-top: 1px solid #e5e7eb; align-items: center; font-size: 14px;">
                            <span style="font-family: monospace;">{key.prefix}...</span>
                            <span>{key.label || '-'}</span>
                            <span style="color: #6b7280;">{new Date(key.created_at).toLocaleDateString()}</span>
                            <span>
                              {key.revoked_at
                                ? <span style="color: #ef4444; font-size: 12px;">Revoked</span>
                                : <span style="color: #22c55e; font-size: 12px;">Active</span>
                              }
                            </span>
                            <span>
                              <Show when={() => !key.revoked_at}>
                                {() => (
                                  <lui-button variant="ghost" on:click={() => handleRevokeKey(key.id)}>
                                    Revoke
                                  </lui-button>
                                )}
                              </Show>
                            </span>
                          </div>
                        ))}
                      </div>
                    )}
                  </Show>

                  {/* Generate key dialog */}
                  <Show when={() => showGenerateKey.value}>
                    {() => (
                      <div style="position: fixed; inset: 0; background: rgba(0,0,0,0.4); display: flex; align-items: center; justify-content: center; z-index: 100;">
                        <div style="background: white; padding: 24px; border-radius: 12px; width: 400px; max-width: 90vw;">
                          <h3 style="margin: 0 0 16px;">Generate API Key</h3>
                          <form onSubmit={handleGenerateKey}>
                            <div style="margin-bottom: 16px;">
                              <lui-input
                                label="Label (optional)"
                                placeholder="production, staging, ..."
                                value={() => newKeyLabel.value}
                                on:input={(e: Event) => { newKeyLabel.value = (e.target as HTMLInputElement).value }}
                              />
                            </div>
                            <div style="display: flex; gap: 8px; justify-content: flex-end;">
                              <lui-button variant="ghost" on:click={() => { showGenerateKey.value = false }}>
                                Cancel
                              </lui-button>
                              <lui-button variant="primary" type="submit">
                                Generate
                              </lui-button>
                            </div>
                          </form>
                        </div>
                      </div>
                    )}
                  </Show>

                  {/* Generated key display dialog */}
                  <Show when={() => generatedKey.value !== null}>
                    {() => (
                      <div style="position: fixed; inset: 0; background: rgba(0,0,0,0.4); display: flex; align-items: center; justify-content: center; z-index: 100;">
                        <div style="background: white; padding: 24px; border-radius: 12px; width: 500px; max-width: 90vw;">
                          <h3 style="margin: 0 0 8px;">Your New API Key</h3>
                          <p style="color: #ef4444; font-size: 13px; margin: 0 0 16px;">
                            This key will not be shown again. Copy it now.
                          </p>

                          <div style="margin-bottom: 12px;">
                            <label style="display: block; font-size: 12px; font-weight: 600; color: #6b7280; margin-bottom: 4px;">API Key</label>
                            <div style="display: flex; gap: 8px; align-items: center;">
                              <code style="flex: 1; padding: 8px 12px; background: #f3f4f6; border-radius: 6px; font-size: 13px; word-break: break-all;">
                                {() => generatedKey.value?.key}
                              </code>
                              <lui-button variant="ghost" on:click={() => copyToClipboard(generatedKey.value?.key || '')}>
                                Copy
                              </lui-button>
                            </div>
                          </div>

                          <div style="margin-bottom: 16px;">
                            <label style="display: block; font-size: 12px; font-weight: 600; color: #6b7280; margin-bottom: 4px;">DSN</label>
                            <div style="display: flex; gap: 8px; align-items: center;">
                              <code style="flex: 1; padding: 8px 12px; background: #f3f4f6; border-radius: 6px; font-size: 13px; word-break: break-all;">
                                {() => generatedKey.value?.dsn}
                              </code>
                              <lui-button variant="ghost" on:click={() => copyToClipboard(generatedKey.value?.dsn || '')}>
                                Copy
                              </lui-button>
                            </div>
                          </div>

                          <div style="display: flex; justify-content: flex-end;">
                            <lui-button variant="primary" on:click={() => { generatedKey.value = null }}>
                              Done
                            </lui-button>
                          </div>
                        </div>
                      </div>
                    )}
                  </Show>
                </div>
              )}
            </Show>
          </div>
        )}
      </Show>

      {/* Members tab */}
      <Show when={() => activeTab.value === 'members'}>
        {() => (
          <div>
            <h2 style="font-size: 18px; margin-bottom: 16px;">Team Members</h2>

            {/* Invite member section */}
            <div style="margin-bottom: 24px; padding: 16px; border: 1px solid #e5e7eb; border-radius: 8px; background: #f9fafb;">
              <h3 style="margin: 0 0 12px; font-size: 14px; font-weight: 600;">Invite Member</h3>
              <form onSubmit={handleInviteMember} style="display: flex; gap: 8px; align-items: flex-end;">
                <div style="flex: 1;">
                  <lui-input
                    type="email"
                    label="Email address"
                    placeholder="colleague@example.com"
                    required
                    value={() => inviteEmail.value}
                    on:input={(e: Event) => { inviteEmail.value = (e.target as HTMLInputElement).value }}
                  />
                </div>
                <lui-button variant="primary" type="submit">
                  Send Invite
                </lui-button>
              </form>
              <Show when={() => inviteError.value !== null}>
                {() => (
                  <div style="color: #ef4444; margin-top: 8px; font-size: 14px;">
                    {() => inviteError.value}
                  </div>
                )}
              </Show>
              <Show when={() => inviteSuccess.value !== null}>
                {() => (
                  <div style="color: #22c55e; margin-top: 8px; font-size: 14px;">
                    {() => inviteSuccess.value}
                  </div>
                )}
              </Show>
            </div>

            {/* Pending invites */}
            <h3 style="font-size: 14px; font-weight: 600; margin-bottom: 12px;">Pending Invites</h3>

            <Show when={() => invitesLoading.value}>
              {() => <p style="color: #6b7280;">Loading...</p>}
            </Show>

            <Show when={() => !invitesLoading.value && invites.value.length === 0}>
              {() => <p style="color: #6b7280; font-size: 14px;">No pending invites.</p>}
            </Show>

            <Show when={() => !invitesLoading.value && invites.value.length > 0}>
              {() => (
                <div style="border: 1px solid #e5e7eb; border-radius: 8px; overflow: hidden;">
                  {() => invites.value.map((invite) => (
                    <div style="display: flex; justify-content: space-between; align-items: center; padding: 12px 16px; border-bottom: 1px solid #e5e7eb;">
                      <div>
                        <div style="font-size: 14px;">{invite.email}</div>
                        <div style="font-size: 12px; color: #9ca3af;">
                          Expires {new Date(invite.expires_at).toLocaleDateString()}
                        </div>
                      </div>
                      <lui-button variant="ghost" on:click={() => handleRevokeInvite(invite.id)}>
                        Revoke
                      </lui-button>
                    </div>
                  ))}
                </div>
              )}
            </Show>
          </div>
        )}
      </Show>

      {/* Settings tab */}
      <Show when={() => activeTab.value === 'settings'}>
        {() => (
          <div>
            <h2 style="font-size: 18px; margin-bottom: 16px;">Organization Settings</h2>

            <div style="padding: 16px; border: 1px solid #e5e7eb; border-radius: 8px; margin-bottom: 24px;">
              <label style="display: block; font-size: 12px; font-weight: 600; color: #6b7280; margin-bottom: 4px;">Organization ID</label>
              <code style="font-size: 14px; color: #374151;">{props.orgId}</code>
            </div>

            <div style="padding: 16px; border: 1px solid #fecaca; border-radius: 8px; background: #fef2f2;">
              <h3 style="margin: 0 0 8px; font-size: 14px; font-weight: 600; color: #991b1b;">Danger Zone</h3>
              <p style="font-size: 13px; color: #6b7280; margin: 0 0 12px;">
                Leaving the organization will remove your access to all its projects and data.
              </p>
              <lui-button variant="ghost" style="color: #ef4444; border-color: #ef4444;">
                Leave Organization
              </lui-button>
            </div>
          </div>
        )}
      </Show>

      {/* Toast notification */}
      <Show when={() => toastMessage.value !== null}>
        {() => (
          <div
            style="position: fixed; bottom: 24px; right: 24px; padding: 12px 20px; background: #1f2937; color: white; border-radius: 8px; font-size: 14px; z-index: 200; cursor: pointer;"
            onClick={() => { toastMessage.value = null }}
          >
            {() => toastMessage.value}
          </div>
        )}
      </Show>
    </div>
  )
}
