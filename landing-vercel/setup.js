(() => {
  const command = '/usr/bin/xattr -dr com.apple.quarantine "/Applications/roma just talk.app" && /usr/bin/open "/Applications/roma just talk.app"';
  const prompt = `Help me set up the early beta of Roma Just Talk on my Mac. I downloaded it from https://github.com/negentropi/roma-just-talk/releases. It has no Apple Developer ID signature and is not notarized.

Find the downloaded app and verify its version and archive checksum against the release notes. Verify its bundle ID against that release's source: v1.95 uses com.prakashjoshipax.VoiceInk; v1.95.1 uses com.negentropi.RomaJustTalk. Move that exact app to Applications without overwriting an existing installation or deleting my data. If there are multiple builds, help me choose the intended one.

Explain that removing com.apple.quarantine skips the downloaded-app Gatekeeper check for this app; it does not make it Apple-approved. After I choose to trust this download, remove only that attribute recursively from the exact app bundle, then open it. Do not disable Gatekeeper globally, re-sign the app, change its bundle ID, reset TCC, or ask for my password.

Guide me through Roma's Permissions page: Microphone for speech, Input Monitoring for the shortcut, and Accessibility for inserting text. Leave optional Screen Recording and Automation off unless I need them. I will handle system authentication myself.

Preserve my existing model and language settings unless I choose to change them. On Apple silicon with macOS 15 or later, offer local Chinese + English (Qwen) or English only (Parakeet V2). First setup uses approximate IP country to suggest Chinese + English in Taiwan, China, Hong Kong, Macao or Singapore; elsewhere or if the lookup fails, it suggests English only. I can choose English only instead of the bilingual suggestion. Download and select the model I choose; for other languages or older Macs, help me choose a supported model.

Keep AI Enhancement off for local-only transcription. Configure Parakeet zh-TW (NVIDIA Cloud) on macOS 15 or later only if I explicitly choose it and provide my own API key; it sends audio to NVIDIA and is not an automatic fallback. Verify the required permissions in Roma, then test dictation into an empty TextEdit document. Report anything that is still blocked.`;

  const dialog = document.createElement('dialog');
  dialog.className = 'setup-dialog';
  dialog.setAttribute('aria-labelledby', 'setup-title');
  dialog.innerHTML = `
    <form method="dialog"><button class="setup-close" aria-label="Close setup guide">Close</button></form>
    <p class="kicker">macOS · early beta</p>
    <h2 id="setup-title" tabindex="-1">After your download finishes</h2>
    <p>Unzip the download, then drag <strong>roma just talk.app</strong> into <strong>Applications</strong>. Choose either setup method below.</p>
    <p>This beta has no Apple Developer ID signature and is not Apple-notarized. The command removes the downloaded-app restriction for this app only. Use it only if you trust this download; it does not make the app Apple-approved.</p>
    <div class="setup-methods">
      <section aria-labelledby="setup-terminal-title">
        <h3 id="setup-terminal-title">Use Terminal</h3>
        <p>After moving the app to Applications, paste this into Terminal and press Return.</p>
        <pre><code id="setup-command"></code></pre>
        <button type="button" class="button secondary" data-copy="setup-command">Copy command</button>
        <p>If Terminal reports a missing app or permission error, use the GUI steps below or the agent prompt.</p>
      </section>
      <section aria-labelledby="setup-agent-title">
        <h3 id="setup-agent-title">Ask your agent</h3>
        <p>Paste into an agent that can help with files and macOS setup.</p>
        <pre><code id="setup-prompt"></code></pre>
        <button type="button" class="button secondary" data-copy="setup-prompt">Copy agent prompt</button>
      </section>
    </div>
    <p id="setup-copy-status" role="status" aria-live="polite"></p>
    <details class="setup-gui">
      <summary>Show GUI steps — Open Anyway</summary>
      <ol>
        <li>Open Applications and double-click roma just talk. Dismiss the macOS warning.</li>
        <li>Open System Settings → Privacy &amp; Security. Scroll to Security, then click Open Anyway for roma just talk.</li>
        <li>Confirm Open and authenticate in the macOS prompt yourself if asked.</li>
      </ol>
      <p>If Open Anyway is unavailable on a managed Mac, contact its administrator.</p>
    </details>
    <h3>Finish inside Roma</h3>
    <p>Use the Permissions page to enable Microphone, Input Monitoring, and Accessibility. Screen Recording and Automation are optional. On Apple silicon with macOS 15 or later, choose local Chinese + English (Qwen) or English only (Parakeet V2).</p>
    <p>First setup may suggest Chinese + English from your approximate IP country: Taiwan, China, Hong Kong, Macao or Singapore. Elsewhere, or if the lookup fails, it suggests English only. You can choose English only instead; your choices and existing settings take priority. Download your selected model, then try dictation in TextEdit.</p>
    <p>A local model with AI Enhancement off keeps transcription local. NVIDIA Cloud (macOS 15+) is optional and manually selected with your own API key; it sends audio to NVIDIA and is never an automatic fallback. Read the <a href="/#trust-release">current beta limitations</a> before granting permissions.</p>`;
  dialog.querySelector('#setup-command').textContent = command;
  dialog.querySelector('#setup-prompt').textContent = prompt;
  document.body.append(dialog);

  window.showMacSetup = () => {
    if (!dialog.open) dialog.showModal();
    dialog.querySelector('#setup-title').focus();
  };

  dialog.addEventListener('click', async (event) => {
    if (event.target.closest('a[href]')) {
      dialog.close();
      return;
    }
    const button = event.target.closest('[data-copy]');
    if (!button) return;
    const code = dialog.querySelector(`#${button.dataset.copy}`);
    const status = dialog.querySelector('#setup-copy-status');
    try {
      await navigator.clipboard.writeText(code.textContent);
      status.textContent = button.dataset.copy === 'setup-command' ? 'Command copied.' : 'Agent prompt copied.';
    } catch {
      const selection = window.getSelection();
      const range = document.createRange();
      range.selectNodeContents(code);
      selection.removeAllRanges();
      selection.addRange(range);
      status.textContent = 'Clipboard unavailable. Text selected — press Command+C to copy.';
    }
  });

  document.addEventListener('click', (event) => {
    if (event.defaultPrevented || event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return;
    const link = event.target.closest('a[href]');
    if (!link) return;
    const url = new URL(link.href);
    if (url.hostname !== 'github.com' || !url.pathname.startsWith('/negentropi/roma-just-talk/releases/download/') || !url.pathname.endsWith('/roma.just.talk.app.zip')) return;
    window.showMacSetup();
  });
})();
