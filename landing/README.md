# roma-just-talk landing

A Sites/vinext landing page for
[roma-just-talk](https://github.com/happyf-weallareeuropean/roma-just-talk).
The page keeps the public pitch focused on speak-before-hotkey dictation, uses
the GitHub-hosted app logo, links the latest macOS release asset, and stores
Windows waitlist signups in D1 when deployed through Sites.

## Prerequisites

- Node.js `>=22.13.0`

## Quick Start

```bash
npm install
npm run db:generate
npm run dev
npm run build
```

## Useful Commands

- `npm run dev`: start local preview
- `npm run db:generate`: generate D1 migrations after schema edits
- `npm run build`: verify Sites-compatible Worker output
