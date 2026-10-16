# Markets Plugin for DMS

A [DankMaterialShell](https://github.com/dankmaterial/DMS) widget plugin that displays near-live market prices and charts directly in your desktop shell through configurable market data providers.

| Dark Theme | Light Theme |
|:---:|:---:|
| <img src="images/Dark-Popup.png" width="400"/> | <img src="images/Light-Popup.png" width="400"/> |

## Features

- **Pin to bar** — display live prices for selected symbols directly in `DankBar`.
- **Popup panel** — list showing name, price, change percentage, and `sparkline` charts.
- **Manual symbol entry** — open the selected provider in your browser, then add the provider symbol manually.
- **Per-symbol configuration** — independent data provider, price resolution, chart resolution, chart range, change display, and price inversion. Each dropdown only offers what the selected provider can actually serve.
- **Provider name on charts** — optionally show the data provider's name in the lower-left corner of each chart (on by default).
- **Chart range validation** — the settings warn when the chart resolution gives very few (< 10) or very many (> 100) candles for the chart range, and don't allow fewer than 3 or more than 200.
- **Custom colors** — configurable up/down color indicators.
- **Reorder & edit** — rearrange symbol order, click to edit, hover to pin or delete.
- **Adjustable popup height** — set the number of visible rows.
- **Intelligent fetching** — staggered data requests with retry logic to avoid rate limiting.

| Settings (1) | Settings (2) |
|:---:|:---:|
| <img src="images/Settings-1-Dark.png" width="400"/> | <img src="images/Settings-2-Dark.png" width="400"/> |

## Requirements

- `DMS` ≥ 1.2.0
- `curl` installed and available in `$PATH`
- `bash` installed and available in `$PATH`
- `Node.js` only when `Stooq` provider is used (currently disabled).
- Internet access

## Data Providers

Currently supported providers:

- [Yahoo Finance](https://finance.yahoo.com) — The current default. No credentials required. Example symbols: `EURUSD=X`, `BZ=F`, `HG=F`, `DX-Y.NYB`, `^GSPC`.
- [Stooq](https://stooq.com) — Currently disabled, due to unstable `API`. Publishes `CSV` quotes for a wide range of instruments.
- [Wise](https://wise.com) — No credentials required. Anonymous currency-exchange rates for most world currencies, including exotic pairs Yahoo Finance does not cover (e.g. `BRLPLN`). Symbols are 6-letter pairs (source then target).

  > **Limitation:** Wise publishes hourly and daily rates only (no sub-hour, weekly or monthly data). Price resolutions are `1 Hour` and `1 Day`; the API serves up to 1 month of hourly and 5 years of daily data, but the settings only offer chart ranges that give a readable number of candles (see below).

  > **Limitation:** Some Stooq symbols (usually futures that has symbols of `*.f` format) shown on the website do not return CSV data through the public API. If a symbol stays empty in the widget, open Stooq in your browser and try the cash/index variant shown there (i.e. symbols of `*.i` or `*.c` format).

## Privacy

- URLs are passed as separate process arguments.
- `Yahoo Finance` provider quires `query1.finance.yahoo.com`, clicking a chart or symbol search opens `finance.yahoo.com` in your browse.
- `Wise` contacts `wise.com`, clicking a chart or symbol search opens `wise.com` in your browser.
- The last prices and charts of your symbols are saved as small JSON files in `~/.cache/dms-markets-plugin/` (or `$XDG_CACHE_HOME/dms-markets-plugin/`); delete the folder any time.
- Responses are written to `mktemp` temporary files and cleaned up when the fetch script exits.
- Stooq contacts `stooq.com`, and stores a cookie jar at `~/.cache/dms-markets-stooq.cookies`, and uses `Node.js` for a browser verification proof-of-work challenge.
- No endpoints are contacted other than the one related to the configured provider.
- Provider credentials (currently only `Stooq`) are stored locally in plugin settings, with simple and reversible XOR obfuscation.
- `Stooq` is operated from `Poland` and is presumably `GDPR`-compliant. See their [Privacy & Cookie Policy](https://stooq.com/privacy/) and [Terms of Service](https://stooq.com/terms.html).
- `Yahoo's` [Privacy Policy](https://legal.yahoo.com/us/en/yahoo/privacy/index.html), [Yahoo Finance privacy practices](https://legal.yahoo.com/us/en/yahoo/privacy/products/mediaservices/index.html#yahoo-finance), and [Terms of Service](https://legal.yahoo.com/us/en/yahoo/terms/otos/index.html).
- `Wise's` [Privacy Policy](https://wise.com/privacypolicy/) and [Terms of Use](https://wise.com/terms-and-conditions).

## Version History

- v1.0.5 :
  - The last prices and charts of every symbol are now kept on disk (one file per symbol in `~/.cache/dms-markets-plugin/`, only the latest update is kept), shown immediately after a start, and refreshed in the background. A failed refresh no longer hides what was already loaded, and "refreshed x ago" tells when the data was really fetched.
  - Saving settings is retried before it is reported as failed. Damaged saved symbols cannot be overwritten until their backup succeeds.
  - Responses and cached data from an earlier symbol configuration are ignored after an edit; displayed errors remain readable when the diagnostic history fills up.
  - New per-symbol `Change Resolution` setting (default `1 Day`, options depend on the provider): the change is measured against the close of the previous period, so it matches the provider's quote page. Saved symbols are migrated to the default.
  - New `Wise` provider, covering exotic pairs `Yahoo Finance` does not offer. No credentials required, thx for [brunofin](https://github.com/brunofin).
  - New `Chart Resolution` that can be set per symbol (before chart resolution was same as price resolution).
  - New `Show Provider Name` setting.
  - Full refactoring for first citizen support of self-declarative multiprovider setup. Note: the saved symbols will be migrated to new formats on first load.
- v1.0.4 :
  - A maintenance release with small fixes, to comply with `DMS` comments [published here](https://github.com/AvengeMedia/dms-plugin-registry/issues/555#issuecomment-5899885512) and [here](https://github.com/AvengeMedia/dms-plugin-registry/pull/990#issuecomment-5947902007).
  - Enforce all command execution via `bash` to not break when user's default shell is not `bash`.
- v1.0.3 :
  - `Stooq` changed their `API` yet again, and broken data fetching.
  - Added `Yahoo Finance` provider as a, probably less privacy respecting, but working alternative for `Stooq`.
  - Disabled `Stooq` till they stabilize their `API`.
  - If you previously configured `Stooq` symbols, delete them and re-add the same markets using another provider. Provider symbols can differ, so use the symbol search link in settings to find the correct Yahoo Finance symbol.
- v1.0.2 :
  - Now `Stooq` requires `API` key to provide historic data, updated backend and widget settings to support `API` key.
  - In-settings search for symbols is removed due to unreliability, replaced with a button to open provider's symbols search web page.
- v1.0.1 (Not published to `DMS`, due to changes from `Stooq` provider):
  - Fixed the issue with charts for previously working symbols, are not displayed (Unfortunately, `Stooq` now requires using cookies).
  - Added logging capability.
  - Refactoring.
- v1.0.0 :
  - Initial version.

## Install

### Method 1

In DMS:

1. Open `Settings -> Plugins`
2. Click `Scan for Plugins`
3. Enable `GitHub Inbox`
4. Add widget to DankBar

### Method 2

Or clone repo, and run (this will add `Symlink` to plugin folder):

```bash
chmod +x support/setup-symlink.sh
support/setup-symlink.sh
```

## Disclaimers

- The developer has no affiliation with any data provider.
- This plugin was vibe-coded under my supervision as a software engineer.

## Contributions

Feel free to submit your PR, try to follow [Code Requirements](docs/code_requirements.md).
