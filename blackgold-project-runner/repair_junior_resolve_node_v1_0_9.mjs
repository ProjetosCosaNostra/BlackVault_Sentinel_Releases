import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import { spawnSync } from 'node:child_process';

const base = path.join(process.env.LOCALAPPDATA || '', 'BlackGoldProjectRunner');
const runnerPath = path.join(base, 'runner.ps1');
const runnerUrl = 'https://raw.githubusercontent.com/ProjetosCosaNostra/BlackVault_Sentinel_Releases/c87346c90c269356c8ad5af850a25c21d6fc102f/blackgold-project-runner/runner.ps1';
const localRoot = 'E:\\Junior_Resolve__RECOVERY_A17_20260917';
const recoveryRef = 'backup/jr-recovered-r63h-node-npmcli-fixed-20260921';
const remoteRef = `refs/remotes/origin/${recoveryRef}`;
const refspec = `+refs/heads/${recoveryRef}:${remoteRef}`;
const nodeApplyPath = path.join(base, 'junior-apply-recovery.mjs');
const receiptPath = path.join(base, 'junior-node-bootstrap-receipt.json');
const taskName = 'BlackGold_Project_Runner_V1';

function run(file, args, { allowFailure = false, capture = false } = {}) {
  const result = spawnSync(file, args, {
    encoding: capture ? 'utf8' : undefined,
    stdio: capture ? ['ignore', 'pipe', 'pipe'] : 'inherit',
    windowsHide: true,
    maxBuffer: 64 * 1024 * 1024,
    env: process.env,
  });
  if (result.error && !allowFailure) throw result.error;
  const code = result.status ?? (result.error ? 1 : 0);
  if (code !== 0 && !allowFailure) {
    const stderr = capture ? String(result.stderr || '').trim() : '';
    throw new Error(`PROCESS_FAILED_${code}: ${file} ${args.join(' ')}${stderr ? `\n${stderr}` : ''}`);
  }
  return result;
}

function count(text, needle) {
  return text.split(needle).length - 1;
}

async function downloadText(url) {
  const response = await fetch(url, { redirect: 'follow' });
  if (!response.ok) throw new Error(`HTTP_${response.status}: ${url}`);
  return await response.text();
}

fs.mkdirSync(base, { recursive: true });

const bootstrap = {
  schema: 1,
  project: 'Junior_Resolve',
  startedAt: new Date().toISOString(),
  recoveryRef,
  status: 'RUNNING',
  mainMerged: false,
  productionMutated: false,
  playPublished: false,
};

try {
  run('schtasks.exe', ['/End', '/TN', taskName], { allowFailure: true });
  run('schtasks.exe', ['/Change', '/TN', taskName, '/DISABLE'], { allowFailure: true });

  console.log('[1/4] Restaurando BlackGold Project Runner V1.0.8 limpo...');
  const runnerText = await downloadText(runnerUrl);
  if (!runnerText.includes("$RunnerVersion = '1.0.8'")) throw new Error('RUNNER_VERSION_MISMATCH');
  if (count(runnerText, 'Set-StrictMode -Version Latest') !== 1) throw new Error('RUNNER_DUPLICATED_STRICTMODE');
  if (count(runnerText, 'function Invoke-Job') !== 1) throw new Error('RUNNER_DUPLICATED_INVOKE_JOB');
  if (!runnerText.includes('JUNIOR_RESOLVE_DIRECT_LAUNCH_BLOCKED_USE_RECOVERY')) throw new Error('RUNNER_MISSING_STALE_LAUNCH_GUARD');
  fs.writeFileSync(runnerPath, runnerText, 'utf8');

  console.log('[2/4] Buscando checkpoint Node da recovery...');
  run('git.exe', ['-C', localRoot, 'fetch', '--force', 'origin', refspec]);
  const show = run('git.exe', ['-C', localRoot, 'show', `${remoteRef}:scripts/recovery/apply-recovery-to-local-android.mjs`], { capture: true });
  const applyText = String(show.stdout || '');
  if (!applyText.includes("project: 'Junior_Resolve'")) throw new Error('NODE_APPLY_PROJECT_MARKER_MISSING');
  if (!applyText.includes("androidInstallDebug: 'PASS'")) throw new Error('NODE_APPLY_ANDROID_PASS_MARKER_MISSING');
  if (!applyText.includes("productionMutated: false")) throw new Error('NODE_APPLY_PRODUCTION_GUARD_MISSING');
  fs.writeFileSync(nodeApplyPath, applyText, 'utf8');

  console.log('[3/4] Validando sintaxe Node antes de executar...');
  run(process.execPath, ['--check', nodeApplyPath]);

  console.log('[4/4] Build + recovery + Android + emulador...');
  run(process.execPath, [
    nodeApplyPath,
    '--local-root', localRoot,
    '--recovery-ref', recoveryRef,
    '--snapshot-root', 'E:\\Junior_Resolve__RECOVERY_SNAPSHOTS',
    '--avd', 'Junior_Resolve_GAPI_Lite_API35_20260909',
  ]);

  run('schtasks.exe', ['/Change', '/TN', taskName, '/ENABLE'], { allowFailure: true });

  bootstrap.status = 'PASS';
  bootstrap.finishedAt = new Date().toISOString();
  bootstrap.runnerRestored = true;
  bootstrap.nodeSyntaxValidated = true;
  bootstrap.recoveryApplied = true;
  fs.writeFileSync(receiptPath, JSON.stringify(bootstrap, null, 2) + os.EOL, 'utf8');

  console.log('');
  console.log('JUNIOR RESOLVE RECOVERY NODE: PASS');
  console.log(`Checkpoint: ${recoveryRef}`);
  console.log(`Receipt: ${receiptPath}`);
  console.log('APK antigo nao foi usado como fonte desta aprovacao.');
} catch (error) {
  bootstrap.status = 'FAIL';
  bootstrap.finishedAt = new Date().toISOString();
  bootstrap.error = error?.stack || String(error);
  fs.writeFileSync(receiptPath, JSON.stringify(bootstrap, null, 2) + os.EOL, 'utf8');
  console.error(bootstrap.error);
  console.error(`Receipt: ${receiptPath}`);
  process.exitCode = 1;
}
