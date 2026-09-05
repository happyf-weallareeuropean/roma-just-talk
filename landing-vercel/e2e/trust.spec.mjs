import { expect, test } from "@playwright/test";

test("Trust details and navigation work by keyboard without starting a download", async ({ page, baseURL }) => {
  const appRequests = [];
  await page.route("**/*", (route) => {
    const url = new URL(route.request().url());
    if (url.origin === new URL(baseURL).origin) return route.continue();
    if (url.pathname.includes("/releases/download/")) appRequests.push(url.href);
    return route.fulfill({ status: 204, body: "" });
  });
  await page.goto("/#trust", { waitUntil: "domcontentloaded" });

  const details = page.locator(".trust-details");
  const summary = details.locator("summary");
  await expect(details).not.toHaveAttribute("open", "");
  await summary.press("Enter");
  await expect(details).toHaveAttribute("open", "");
  await expect(page.getByRole("heading", { name: "What Roma reads and sends", exact: true })).toBeVisible();
  await summary.press("Space");
  await expect(details).not.toHaveAttribute("open", "");

  await page.getByRole("link", { name: "Getting help", exact: true }).press("Enter");
  await expect(page).toHaveURL(/#trust-support$/);
  await expect(page.locator("#trust-support")).toBeInViewport();
  expect(appRequests).toEqual([]);
});
