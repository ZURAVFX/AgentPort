# Public Release Checklist

## GitHub
- [x] Publish Web2AE source under `Public_tools/Web2AE`
- [ ] Create release tag `v1.0.0`
- [ ] Upload `Web2AE_v1.0.0_Companion_Windows.zip` as a release asset if desired

## Chrome Web Store
- [ ] Upload `Web2AE_v1.0.0_Chrome_Store.zip`
- [ ] Category: Developer Tools or Productivity
- [ ] Upload store icon/screenshots/promo tile
- [ ] Paste description from `docs/STORE_COPY.md`
- [ ] Add privacy-policy URL pointing to `docs/PRIVACY.md`
- [ ] Explain optional `debugger` permission as current-tab DOM/render-tree snapshot access

## Firefox Add-ons (AMO)
- [ ] Upload `Web2AE_v1.0.0_Firefox_AMO.zip`
- [ ] Confirm data collection declaration is `none`
- [ ] Add source repository and privacy-policy URLs

## Before pressing Publish
- [ ] Verify extension + companion both show v1.0.0
- [ ] Test Chrome from final ZIP
- [ ] Test Firefox from final ZIP
- [ ] Confirm privacy/support URLs are public
