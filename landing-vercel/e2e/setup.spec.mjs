import { expect, test } from '@playwright/test';

async function prepare(page, baseURL) {
  await page.route('**/*', route => {
    const url = new URL(route.request().url());
    if (url.origin === new URL(baseURL).origin) return route.continue();
    if (url.pathname.includes('/releases/download/')) {
      return route.fulfill({ status: 200, headers: { 'Content-Disposition': 'attachment; filename="roma.just.talk.app.zip"' }, contentType: 'application/zip', body: 'download fixture' });
    }
    return route.fulfill({ status: 200, contentType: 'application/json', body: '[]' });
  });
}

for (const viewport of [{ width: 1280, height: 900 }, { width: 390, height: 844 }]) {
  test(`download exposes both setup methods at ${viewport.width}px`, async ({ page, context, baseURL }) => {
    await page.setViewportSize(viewport);
    await prepare(page, baseURL);
    await context.grantPermissions(['clipboard-read', 'clipboard-write']);
    await page.goto('/');
    const download = page.waitForEvent('download');
    await page.getByRole('link', { name: /download macos \(early beta\)/ }).click();
    expect((await download).suggestedFilename()).toBe('roma.just.talk.app.zip');
    const dialog = page.getByRole('dialog');
    await expect(dialog).toBeVisible();
    await expect(dialog.locator('#setup-title')).toBeFocused();
    await expect(dialog.locator('details')).not.toHaveAttribute('open', '');
    await dialog.getByRole('button', { name: 'Copy command', exact: true }).click();
    await expect(dialog.getByRole('status')).toHaveText('Command copied.');
    expect(await page.evaluate(() => navigator.clipboard.readText())).toContain('/Applications/roma just talk.app');
    await dialog.getByRole('button', { name: 'Copy agent prompt' }).click();
    await expect(dialog.getByRole('status')).toHaveText('Agent prompt copied.');
    expect(await page.evaluate(() => navigator.clipboard.readText())).toContain('com.negentropi.RomaJustTalk');
    await dialog.locator('summary').press('Enter');
    await expect(dialog.locator('details')).toHaveAttribute('open', '');
    expect(await dialog.evaluate(el => el.scrollWidth <= el.clientWidth)).toBe(true);
    await dialog.screenshot({ path: `test-results/setup-${viewport.width}.png` });
    await page.keyboard.press('Escape');
    await expect(dialog).not.toBeVisible();
  });
}

test('clipboard rejection offers manual copy; dialog keyboard does not download again', async ({ page, baseURL }) => {
  await prepare(page, baseURL);
  await page.addInitScript(() => Object.defineProperty(navigator, 'clipboard', { value: { writeText: () => Promise.reject(new Error('denied')) } }));
  await page.goto('/');
  let downloads = 0;
  page.on('download', () => downloads++);
  const download = page.waitForEvent('download');
  await page.locator('body').press('Enter');
  await download;
  await page.getByRole('button', { name: 'Copy command', exact: true }).click();
  await expect(page.getByRole('status')).toContainText('press Command+C');
  expect(await page.evaluate(() => window.getSelection().toString())).toContain('com.apple.quarantine');
  await page.locator('#setup-title').press('Enter');
  expect(downloads).toBe(1);
});

test('pricing download also opens setup', async ({ page, baseURL }) => {
  await prepare(page, baseURL);
  await page.goto('/pricing');
  const download = page.waitForEvent('download');
  await page.getByRole('link', { name: 'download current build (early beta)' }).click();
  await download;
  await expect(page.getByRole('dialog')).toBeVisible();
});

test('dark setup stays readable and limitations link closes the modal', async ({ page, baseURL }) => {
  await prepare(page, baseURL);
  await page.emulateMedia({ colorScheme: 'dark' });
  await page.goto('/');
  const download = page.waitForEvent('download');
  await page.getByRole('link', { name: /download macos \(early beta\)/ }).click();
  await download;
  const colors = await page.locator('#setup-command').evaluate(el => ({
    foreground: getComputedStyle(el).color,
    background: getComputedStyle(el.parentElement).backgroundColor,
  }));
  expect(colors).toEqual({ foreground: 'rgb(255, 248, 231)', background: 'rgb(5, 5, 5)' });
  await page.getByRole('dialog').screenshot({ path: 'test-results/setup-dark.png' });
  await page.getByRole('link', { name: 'current beta limitations' }).click();
  await expect(page.getByRole('dialog')).not.toBeVisible();
  await expect(page).toHaveURL(/#trust-release$/);
  await expect(page.locator('#trust-release')).toBeInViewport();
});
