import { defineConfig } from 'vite';
import aitDevtools from '@apps-in-toss/devtools/unplugin';

export default defineConfig({
  plugins: [aitDevtools.vite()],
  base: './',
  build: { assetsInlineLimit: 0, target: 'es2022' },
});
