# Firefox Add-ons Submission Notes — Web2AE v1.0.0

## Purpose
Transfer the current user-selected live webpage into Adobe After Effects layers.

## Permissions
- `activeTab`: access only the tab the user explicitly captures.
- `scripting`: run the Web2AE live-DOM collector on that tab.
- `http://127.0.0.1:17321/*`: send the capture to the local After Effects companion.

## Firefox data-transmission declaration
Firefox 140+ uses Mozilla’s built-in data collection/transmission disclosure. Web2AE declares:

```json
"data_collection_permissions": {
  "required": ["browsingActivity", "websiteContent"]
}
```

This is required because an explicit capture transfers the current page URL/title and visible website content from the browser extension to the Web2AE companion at `127.0.0.1`. The data stays on the user’s own computer and is not sent to Elliot/zura or any third party.

The transfer is user-initiated and is the extension’s single, self-evident function. No passive/background browsing collection occurs.

## Source code
The add-on is unminified and unobfuscated. Full source is included in the public GitHub repository.

## Companion
Requires the free open-source Web2AE After Effects companion on Windows.

## Suggested reviewer note
> Web2AE transfers only the current tab selected by the user, and only after the user presses “Send Current Page to AE”. The page URL/title, rendered website content and visible viewport screenshot are sent to `http://127.0.0.1:17321`, where the local Adobe After Effects companion reconstructs the page as layers. No captured content leaves the user’s machine. There are no analytics, ads, accounts or cloud services.
