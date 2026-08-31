# Web2AE v1.0 User Guide

## 1. Install the companion

1. Download `Web2AE_v1.0.0_Companion_Windows.zip`.
2. Extract the ZIP.
3. Double-click **Install Web2AE.bat**.
4. Restart After Effects.
5. Open **Window → Extensions → Web2AE**.

> Browser security does not allow a Chrome/Firefox extension to silently install native After Effects files. The companion install is intentionally a separate one-time step.

## 2. Install the browser extension

Install Web2AE from the Chrome Web Store or Firefox Add-ons. The extension asks only for the page access needed when you click it. Chrome can optionally request the `debugger` permission on first high-fidelity capture; Web2AE uses that only to read the current tab's render tree and detaches immediately after capture.

## 3. Capture a page

1. Open the page and scroll to the exact viewport you want.
2. Make sure **Web2AE is open in After Effects**.
3. Click the Web2AE browser icon.
4. Click **Send Current Page to AE**.
5. Web2AE analyses the browser's current rendered elements and sends the scene to After Effects through `127.0.0.1`.

## 4. What appears in After Effects

Web2AE chooses the safest representation for each element:

- **Text** → editable AE text whenever CSS is compatible.
- **Buttons/cards/backgrounds** → native AE rectangles/fills/strokes where possible.
- **Images/thumbnails/avatars** → source/raster element layers with clipping and rounded masks.
- **Complex visual effects** → tightly bounded pixel-accurate fallback layers.
- **Sections/cards** → precomps only when grouping will not break browser paint order.

The optional `REFERENCE — Browser Capture` layer is hidden by default and lets you compare the reconstruction against the original browser pixels.

## Recommended workflow

- Capture at the exact browser zoom and viewport you intend to animate.
- Wait for lazy-loaded images to finish loading before capture.
- For infinite feeds, capture one visible viewport at a time.
- Keep **editable text** enabled unless exact typographic fidelity matters more than editability.
- If a page uses unusual blend modes, filters, canvas or DRM video, expect those elements to remain raster.

## Troubleshooting

### The browser says “Open Web2AE in After Effects”
Open **Window → Extensions → Web2AE** in After Effects. The panel runs the local bridge only while After Effects is open.

### The browser captured zero elements
Reload the page and the browser extension. Protected browser pages, extension stores and internal URLs cannot be inspected like normal webpages.

### Fonts do not match exactly
Web2AE uses the font names reported by the browser. Install the same font locally in Windows/Adobe, or keep the element as raster when exact pixel fidelity is critical.

### A complex element is raster instead of editable
That is intentional when native AE reconstruction would be visibly wrong. Web2AE prioritises visual fidelity over pretending unsupported CSS is editable.

### Firefox differs from Chrome/Edge
Chromium provides a richer render-tree snapshot API. Firefox uses the live-DOM collector, so closed Shadow DOM and inaccessible cross-origin iframe internals may be retained as larger exact-pixel elements.

## Privacy

Web2AE processes the current visible page only when you press **Send Current Page to AE**. It does not collect browsing history, analytics, account data or page contents for the developer. Captures are sent only to the local companion on `127.0.0.1`.
