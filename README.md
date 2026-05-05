# Markets Plugin for DMS

A [DankMaterialShell](https://github.com/dankmaterial/DMS) widget plugin that displays near-live market prices and charts directly in your desktop shell, using free to obtain `API` key.

| Dark Theme | Light Theme |
|:---:|:---:|
| <img src="Images/Dark-Popup.png" width="400"/> | <img src="Images/Light-Popup.png" width="400"/> |

## Features

- **Pin to bar** — display live prices for selected symbols directly in `DankBar`.
- **Popup panel** — list showing name, price, change percentage, and `sparkline` charts.
- **Symbol search** — find and add symbols by keyword via provider search `API`.
- **Per-symbol configuration** — independent price interval, chart range, change display, and price inversion.
- **Custom colors** — configurable up/down color indicators.
- **Reorder & edit** — rearrange symbol order, click to edit, hover to pin or delete.
- **Adjustable popup height** — set the number of visible rows.
- **Intelligent fetching** — staggered data requests with retry logic to avoid rate limiting.

| Settings (1) | Settings (2) |
|:---:|:---:|
| <img src="Images/Settings-1-Dark.png" width="400"/> | <img src="Images/Settings-2-Dark.png" width="400"/> |

## Requirements

- `DMS` ≥ 1.2.0
- `curl` installed and available in `$PATH`
- Internet access
- Free `Stooq` `API` key (see below how to obtain it).

## Data Providers

Currently supported only one provider: [Stooq](https://stooq.com) that publishes free `CSV` quotes for a wide range of instruments. A free API key is required.


### Getting a Free Stooq API Key

1. Open [stooq.com/q/d/?s=eurusd&get_apikey](https://stooq.com/q/d/?s=eurusd&get_apikey) in your browser.
2. Enter the captcha code shown on the page.
3. Copy the CSV download link shown at the bottom of the page (it contains your `apikey` value).
4. Paste the link in some text editor, and copy the last part of the link after `apikey=`, and paste it in the plugin **Settings** before adding symbols.

> **Limitation:** `Stooq` does not provide historical data for futures symbols (tickers matching `*.f`) through its public `API`. Price data will load, but charts will be unavailable for these symbols.

## Privacy

- No endpoints are contacted other than the configured data provider.
- All requests are made without cookies to minimize tracking potential. (However, see [Version History](#version-history))
- `Stooq` is operated from `Poland` and is presumably `GDPR`-compliant. See their [Privacy & Cookie Policy](https://stooq.com/privacy/) and [Terms of Service](https://stooq.com/terms.html).

## Version History

- v1.0.2 :
  - Now `Stooq` requires `API` key to provide historic data, updated backend and widget settings to support `API` key.
- v1.0.1 (Unpublished, due to following changes from `Stooq` provider):
  - Fixed the issue with charts for previously working symbols, are not displayed (Unfortunately, `Stooq` now requires using cookies).
  - Added logging capability.
  - Refactoring.
- v1.0.0 :
  - Initial version.

## Disclaimers

- The developer has no affiliation with any data provider.
- This plugin was vibe-coded under my supervision as a software engineer.
