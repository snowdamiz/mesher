/**
 * Centralized API client for all Mesher backend endpoints.
 * Uses fetch with credentials: 'include' to send session cookies.
 */

async function request<T = unknown>(method: string, path: string, body?: unknown): Promise<T> {
  const opts: RequestInit = {
    method,
    credentials: 'include',
    headers: body ? { 'Content-Type': 'application/json' } : {},
    body: body ? JSON.stringify(body) : undefined,
  }
  const res = await fetch(path, opts)
  const data = await res.json().catch(() => ({}))
  if (!res.ok) throw { status: res.status, ...data }
  return data as T
}

export const api = {
  auth: {
    register: (email: string, password: string) =>
      request('POST', '/api/auth/register', { email, password }),
    login: (email: string, password: string) =>
      request('POST', '/api/auth/login', { email, password }),
    logout: () =>
      request('POST', '/api/auth/logout'),
    me: () =>
      request<{ id: string; email: string }>('GET', '/api/auth/me'),
    resetPassword: (email: string) =>
      request('POST', '/api/auth/reset-password', { email }),
    confirmReset: (token: string, password: string) =>
      request('POST', '/api/auth/reset-password/confirm', { token, new_password: password }),
  },
  config: {
    tier: () =>
      request<{ tier: string }>('GET', '/api/config/tier'),
  },
  orgs: {
    create: (name: string) =>
      request<{ id: string; name: string; schema_name: string }>('POST', '/api/orgs', { name }),
    list: () =>
      request<{ organizations: Array<{ id: string; name: string }> }>('GET', '/api/orgs'),
    get: (id: string) =>
      request<{ id: string; name: string }>('GET', `/api/orgs/${id}`),
    invites: {
      create: (orgId: string, email: string) =>
        request<{ id: string; email: string; expires_at: string }>('POST', `/api/orgs/${orgId}/invites`, { email }),
      list: (orgId: string) =>
        request<{ invites: Array<{ id: string; email: string; expires_at: string }> }>('GET', `/api/orgs/${orgId}/invites`),
      revoke: (orgId: string, inviteId: string) =>
        request('DELETE', `/api/orgs/${orgId}/invites/${inviteId}`),
      accept: (token: string) =>
        request<{ status: string; org_id: string }>('POST', `/api/invites/${token}/accept`),
    },
    projects: {
      create: (orgId: string, name: string) =>
        request<{ id: string; name: string }>('POST', `/api/orgs/${orgId}/projects`, { name }),
      list: (orgId: string) =>
        request<{ projects: Array<{ id: string; name: string; created_at: string }> }>('GET', `/api/orgs/${orgId}/projects`),
    },
    apiKeys: {
      create: (orgId: string, projectId: string, label?: string) =>
        request<{ id: string; key: string; prefix: string; dsn: string }>('POST', `/api/orgs/${orgId}/projects/${projectId}/api-keys`, { label }),
      list: (orgId: string, projectId: string) =>
        request<{ api_keys: Array<{ id: string; prefix: string; label: string; created_at: string; revoked_at: string | null }> }>('GET', `/api/orgs/${orgId}/projects/${projectId}/api-keys`),
      revoke: (orgId: string, keyId: string) =>
        request('POST', `/api/orgs/${orgId}/api-keys/${keyId}/revoke`),
    },
  },
}
