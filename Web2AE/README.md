# Web2AE

**Turn a live webpage into editable After Effects layers.**

Web2AE captures the page you are actually viewing in Chrome, Edge or Firefox and rebuilds the visible viewport in Adobe After Effects using editable text, native shapes, image/raster elements and sensible groups wherever practical.

**Free. Open source. Local-only. No API keys. No subscription.**

Created by **Elliot Mckenzie / zura**.

## What it does

- Captures the **current live browser state**, including logged-in/dynamic pages you can already see.
- Rebuilds normal text as **editable After Effects text layers**.
- Rebuilds flat UI backgrounds, borders and rounded controls as **native shape layers**.
- Keeps thumbnails, photos, video frames, canvas content and difficult CSS as **pixel-accurate element-sized raster layers**.
- Preserves CSS clipping and rounded corners where possible.
- Groups semantic sections/cards into precomps when doing so is paint-order safe.
- Keeps an optional hidden browser screenshot as a fidelity reference.
- Sends page data only to the local Web2AE bridge at `127.0.0.1:17321`.

## Requirements

- Windows 10/11
- Adobe After Effects 2024 or newer
- Chrome, Microsoft Edge or Firefox

## Installation

Web2AE has two small pieces: the browser extension and the After Effects companion.

### 1. Install the After Effects companion

Download [`Web2AE_v1.0.0_Companion_Windows.zip`](releases/Web2AE_v1.0.0_Companion_Windows.zip), extract it, run **Install Web2AE.bat**, restart After Effects, then open:

**Window → Extensions → Web2AE**

### 2. Install the browser extension

The Chrome Web Store and Firefox Add-ons listings are being prepared for v1. Development builds can be loaded unpacked from [`browser-extension/`](browser-extension/).

### 3. Capture

Open the webpage you want, click the Web2AE browser icon, then choose **Send Current Page to AE**.

See the full [User Guide](docs/USER_GUIDE.md).

## Why the companion cannot install silently from Chrome/Firefox

Browser extensions are intentionally sandboxed and cannot silently write an After Effects CEP extension into Adobe's application folders or execute a native installer. Web2AE therefore uses a one-time companion installer. After that, browser captures are one-click.

## Privacy

Web2AE does not send browsing data to the developer or any cloud service. The page capture is sent only to the local After Effects companion on your own computer. See [Privacy Policy](docs/PRIVACY.md).

## Known boundaries

Web2AE targets normal webpages. Browser-internal pages (`chrome://`, `about:`), extension stores, DRM-protected media and some inaccessible cross-origin/closed browser surfaces cannot be captured like normal pages. Complex CSS may be retained as exact element-sized pixels instead of becoming native AE primitives.

## Licence

MIT. See [LICENSE](LICENSE).
