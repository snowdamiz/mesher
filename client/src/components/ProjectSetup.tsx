/**
 * Project setup / onboarding component.
 *
 * Displayed after a user creates a project and generates an API key.
 * Shows the DSN, npm install command, @sentry/node setup code snippet
 * with DSN pre-filled, and a test error snippet.
 *
 * Props:
 *   - projectId: The project UUID
 *   - apiKey: The raw API key (shown once at creation time)
 *
 * This is a display-only component with no API calls. The only state
 * management is the copy-to-clipboard confirmation signal.
 */
import { signal } from '@streeem/core'
import { Show } from '@streeem/dom'

interface ProjectSetupProps {
  projectId: string
  apiKey: string
}

export function ProjectSetup(props: ProjectSetupProps) {
  const copiedField = signal<string | null>(null)

  // Build the DSN from props + current host
  const host = typeof window !== 'undefined' ? window.location.host : 'localhost:8080'
  const protocol = typeof window !== 'undefined' ? window.location.protocol : 'https:'
  const dsn = `${protocol}//${props.apiKey}@${host}/api/${props.projectId}`

  function copyToClipboard(text: string, field: string) {
    navigator.clipboard.writeText(text).then(() => {
      copiedField.value = field
      setTimeout(() => {
        if (copiedField.value === field) {
          copiedField.value = null
        }
      }, 2000)
    })
  }

  const setupCode = `import * as Sentry from "@sentry/node";

Sentry.init({
  dsn: "${dsn}",
  environment: "production", // or "staging", "development"
  // Optional: set release version
  // release: "my-app@1.0.0",
});`

  const testCode = `// Trigger a test error
Sentry.captureException(new Error("Test error from Mesher setup"));`

  // Styles
  const sectionStyle = 'margin-bottom: 24px;'
  const labelStyle = 'display: block; font-size: 12px; font-weight: 600; color: #6b7280; margin-bottom: 6px; text-transform: uppercase; letter-spacing: 0.05em;'
  const codeBlockStyle = 'padding: 12px 16px; background: #1f2937; color: #e5e7eb; border-radius: 8px; font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace; font-size: 13px; line-height: 1.5; overflow-x: auto; white-space: pre;'
  const copyBtnStyle = 'padding: 4px 12px; font-size: 12px; border: 1px solid #d1d5db; border-radius: 6px; background: #fff; color: #374151; cursor: pointer;'
  const copiedBtnStyle = 'padding: 4px 12px; font-size: 12px; border: 1px solid #22c55e; border-radius: 6px; background: #f0fdf4; color: #16a34a; cursor: default;'

  return (
    <div style="max-width: 640px;">
      <h2 style="margin: 0 0 4px; font-size: 20px; font-weight: 600;">Set up error reporting</h2>
      <p style="color: #6b7280; margin: 0 0 24px; font-size: 14px;">
        Follow these steps to start capturing errors from your Node.js application.
      </p>

      {/* Step 1: DSN */}
      <div style={sectionStyle}>
        <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 6px;">
          <label style={labelStyle}>1. Your DSN</label>
          <button
            style={() => copiedField.value === 'dsn' ? copiedBtnStyle : copyBtnStyle}
            onClick={() => copyToClipboard(dsn, 'dsn')}
          >
            {() => copiedField.value === 'dsn' ? 'Copied!' : 'Copy'}
          </button>
        </div>
        <div style={codeBlockStyle + ' word-break: break-all; white-space: pre-wrap;'}>
          {dsn}
        </div>
      </div>

      {/* Step 2: Install */}
      <div style={sectionStyle}>
        <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 6px;">
          <label style={labelStyle}>2. Install the SDK</label>
          <button
            style={() => copiedField.value === 'install' ? copiedBtnStyle : copyBtnStyle}
            onClick={() => copyToClipboard('npm install @sentry/node', 'install')}
          >
            {() => copiedField.value === 'install' ? 'Copied!' : 'Copy'}
          </button>
        </div>
        <div style={codeBlockStyle}>
          npm install @sentry/node
        </div>
      </div>

      {/* Step 3: Setup code */}
      <div style={sectionStyle}>
        <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 6px;">
          <label style={labelStyle}>3. Initialize Sentry</label>
          <button
            style={() => copiedField.value === 'setup' ? copiedBtnStyle : copyBtnStyle}
            onClick={() => copyToClipboard(setupCode, 'setup')}
          >
            {() => copiedField.value === 'setup' ? 'Copied!' : 'Copy'}
          </button>
        </div>
        <div style={codeBlockStyle}>
          {setupCode}
        </div>
      </div>

      {/* Step 4: Test it */}
      <div style={sectionStyle}>
        <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 6px;">
          <label style={labelStyle}>4. Test it</label>
          <button
            style={() => copiedField.value === 'test' ? copiedBtnStyle : copyBtnStyle}
            onClick={() => copyToClipboard(testCode, 'test')}
          >
            {() => copiedField.value === 'test' ? 'Copied!' : 'Copy'}
          </button>
        </div>
        <div style={codeBlockStyle}>
          {testCode}
        </div>
      </div>

      {/* Confirmation note */}
      <div style="padding: 12px 16px; background: #eff6ff; border: 1px solid #bfdbfe; border-radius: 8px; font-size: 13px; color: #1e40af;">
        After running the test snippet, check your Mesher dashboard to see the error appear.
        It should show up within a few seconds as a new issue.
      </div>
    </div>
  )
}
