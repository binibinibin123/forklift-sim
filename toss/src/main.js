import { Screen } from '@apps-in-toss/web-framework';
import './bridge.js';

async function landscape() {
  try {
    if (!Screen.setOrientation.isSupported || Screen.setOrientation.isSupported()) {
      await Screen.setOrientation({ type: 'landscape' });
    }
  } catch (e) { console.warn('orientation', e); }
}

window.addEventListener('pagehide', () => {
  Screen.setOrientation({ type: 'portrait' }).catch(() => {});
});

const bar = document.querySelector('#bar > div');
const loading = document.getElementById('loading');

await landscape();
const config = await (await fetch('./game/config.json')).json();
const engine = new Engine({ ...config, executable: 'game/index', canvas: document.getElementById('canvas') });
engine.startGame({
  onProgress: (cur, total) => { if (total > 0) bar.style.width = `${(100 * cur) / total}%`; },
}).then(() => {
  loading.remove();
}).catch((e) => {
  console.error(e);
  loading.firstChild.textContent = '불러오지 못했어요. 다시 열어 주세요.';
});
