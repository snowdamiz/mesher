import { defineConfig } from 'vite'
import { streemHMR } from '@streeem/dom'

export default defineConfig({
  plugins: [streemHMR()],
  esbuild: {
    jsx: 'automatic',
    jsxImportSource: '@streeem/dom',
  },
  server: {
    proxy: {
      '/api': {
        target: 'http://localhost:8080',
        changeOrigin: true,
      },
    },
  },
})
