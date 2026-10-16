// Godot 웹 빌드를 public/game 에 만들고, 엔진 설정을 config.json 으로 꺼낸다.
// 사용: GODOT=/path/to/godot npm run godot
import { execFileSync } from 'node:child_process';
import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';

const godot = process.env.GODOT || 'godot';
mkdirSync('public/game', { recursive: true });
execFileSync(godot, ['--headless', '--path', '..', '--export-release', 'Web', 'toss/public/game/index.html'], { stdio: 'inherit' });
const html = readFileSync('public/game/index.html', 'utf8');
const m = html.match(/const GODOT_CONFIG = (\{.*?\});/);
if (!m) throw new Error('GODOT_CONFIG not found');
const cfg = JSON.parse(m[1]);
cfg.fileSizes = Object.fromEntries(Object.entries(cfg.fileSizes).map(([k, v]) => [`game/${k}`, v]));
writeFileSync('public/game/config.json', JSON.stringify(cfg));
console.log('ok', cfg.fileSizes);
