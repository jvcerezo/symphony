import { spawn } from 'node:child_process';

const RESTART_DELAY_MS = 5_000;

/**
 * Keeps the PO token helper running beside the bot. YouTube asks cloud
 * servers to prove they are not bots; this helper (bgutil-ytdlp-pot-provider)
 * makes that proof, and a yt-dlp plugin fetches it from 127.0.0.1:4416.
 * Without it, yt-dlp still works wherever YouTube is not blocking.
 */
export function startPotServer(scriptPath) {
  let stopped = false;
  let child = null;

  const start = () => {
    child = spawn(process.execPath, [scriptPath], { stdio: ['ignore', 'ignore', 'pipe'], windowsHide: true });
    child.stderr.setEncoding('utf8').on('data', (d) => console.warn(`[po-token] ${d.trim()}`));
    child.on('error', (e) => console.warn('[po-token] could not start:', e.message));
    child.on('exit', (code) => {
      if (stopped) return;
      console.warn(`[po-token] stopped (exit ${code}); restarting.`);
      setTimeout(start, RESTART_DELAY_MS).unref();
    });
  };
  start();
  console.log('PO token helper started.');

  return () => {
    stopped = true;
    child?.kill();
  };
}
