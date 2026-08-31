# Firefox Add-ons Submission Notes — Web2AE v1.0.0

## Purpose
Transfer the current user-selected live webpage into Adobe After Effects layers.

## Permissions
- `activeTab`: access only the tab the user explicitly captures.
- `scripting`: run the Web2AE live-DOM collector on that tab.
- `http://127.0.0.1:17321/*`: send the capture to the local After Effects companion.

## Data collection declaration
`browser_specific_settings.gecko.data_collection_permissions.required = ["none"]`

Web2AE does not collect or transmit user data to the developer or third parties. Page content is processed only for the user's explicit capture and is sent locally to `127.0.0.1`.

## Source code
The add-on is unminified and unobfuscated. Full source is included in the public GitHub repository.

## Companion
Requires the free open-source Web2AE After Effects companion on Windows.
