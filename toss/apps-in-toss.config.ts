import { defineConfig } from '@apps-in-toss/web-framework/config';

export default defineConfig({
  appName: 'forklift-sim', // 토스 콘솔에 등록한 appName과 같아야 함
  brand: {
    primaryColor: '#F5A623',
  },
  permissions: [],
  webBundleDir: 'dist',
});
