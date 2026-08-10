# Homebrew cask release

After GitHub release `vX.Y.Z` finishes, copy SHA-256 from
`WallpaperSelector-X.Y.Z.dmg.sha256` into `wallpaper-selector.rb.template`.
Replace `VERSION` and `SHA256`, then commit result as
`Casks/wallpaper-selector.rb` in `wiggly-sheets/homebrew-tap`.

```bash
brew install --cask wiggly-sheets/tap/wallpaper-selector
```
