# Web2AE Privacy Policy

**Effective date: 31 August 2026**

Web2AE is a local browser-to-After-Effects utility created by Elliot Mckenzie / zura.

## Data Web2AE accesses

When the user explicitly presses **Send Current Page to AE**, Web2AE reads information needed to reconstruct the current visible browser tab, including page structure, rendered text, element geometry, computed visual styles, page URL/title and a screenshot of the visible viewport.

## How the data is used

The data is used only to provide Web2AE's single user-facing function: transferring the current webpage into Adobe After Effects layers.

## Where the data goes

Web2AE does **not** transmit page contents, browsing activity or captured screenshots to the developer, analytics providers, advertisers or any cloud service. Capture data is sent only to the Web2AE After Effects companion running on the same computer at `127.0.0.1`.

## Storage

The browser extension does not maintain browsing history or a remote account. The After Effects companion may create temporary local working files needed to build the current composition. Users can delete these local working files at any time.

## Selling or advertising

Web2AE does not sell user data and does not use captured data for advertising, profiling or tracking.

## Permissions

- `activeTab`: accesses only the tab the user explicitly chooses to capture.
- `scripting`: runs the local capture collector in the selected tab.
- `debugger` (Chrome/Edge, optional): reads Chromium's render-tree/DOM snapshot for higher-fidelity element geometry. Web2AE attaches only during an explicit capture and detaches immediately afterwards.
- `127.0.0.1:17321`: communicates with the local After Effects companion.

## Contact

For privacy questions, open an issue in the Web2AE GitHub repository or use the support contact listed on the official Web2AE download page.
