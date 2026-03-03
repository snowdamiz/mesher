import { defineConfig } from 'vite'
import streem from 'streem/vite'

export default defineConfig({
  plugins: [streem()],
  server: {
    proxy: {
      '/api': {
        target: 'http://localhost:8080',
        changeOrigin: true,
      },
    },
  },
})
