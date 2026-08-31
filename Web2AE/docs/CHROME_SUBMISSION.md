# Chrome Web Store Submission Notes — Web2AE v1.0.0

## Single purpose
Web2AE transfers the webpage the user explicitly chooses into Adobe After Effects as editable/layered artwork.

## Permissions justification

### activeTab
Required to inspect only the current tab after the user explicitly clicks **Send Current Page to AE**. Web2AE does not request persistent access to all websites.

### scripting
Required to run the Web2AE page collector in the current user-selected tab when a Chromium render-tree snapshot is unavailable or additional live-DOM detail is needed.

### debugger (optional)
Requested only when the user initiates a capture in Chrome/Edge. Web2AE uses Chrome DevTools Protocol `DOMSnapshot`/layout information to obtain high-fidelity rendered element geometry, computed styles and paint order for the current tab. The extension detaches immediately after the snapshot. If the user declines this optional permission, Web2AE falls back to its normal live-DOM collector.

### http://127.0.0.1:17321/*
Required to send the user's explicit capture to the Web2AE After Effects companion running on the same computer. No developer/cloud server is contacted.

## Data handling / privacy practices
Web2AE processes website content only when the user explicitly starts a capture. The capture can include the current page URL/title, rendered text, element geometry/styles and an image of the visible viewport. This data is used only for the single purpose of creating After Effects layers.

Data is sent only to `127.0.0.1` on the user's computer. It is not sold, used for advertising, analytics, profiling or transmitted to the developer.

## Remote code
None. All executable extension JavaScript ships inside the extension package.

## Companion application
Web2AE requires a free open-source After Effects companion. Browser security prevents an extension from silently installing native/Adobe files, so the companion is a separate one-time installer.

## Suggested category
Developer Tools (preferred) or Productivity.
