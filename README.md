# Markets Plugin for DMS

A [DankMaterialShell](https://github.com/dankmaterial/DMS) widget plugin that displays live market prices from [Stooq](https://stooq.com) — forex, indices, commodities, crypto, and equities.

## Features

- **Bar pills** — pinned symbols show live prices directly in DankBar
- **Popout panel** — scrollable list with name, price, change, and sparkline chart
- **Stooq search** — find symbols by keyword (autocomplete)
- **Configurable per symbol** — price range, chart range, show-change toggle
- **Configurable colors** — separate up/down hex colors
- **Reorder & edit** — drag symbols up/down, click to edit, hover to pin/delete
- **Adjustable popup height** — slider from 1–50 visible rows

## Project structure

```
plugin.json             Plugin manifest (id, paths, permissions)
QML/
  Widget.qml            Main PluginComponent — bar pills + popout + data fetching
  Settings.qml          PluginSettings — add/edit/remove symbols, colors, layout
  SymbolRow.qml          Popout symbol card (name, price, chart, hover actions)
  PriceChart.qml         Canvas sparkline / area chart
  SymbolSearch.qml       Stooq search input + results
  ConfiguredSymbol.qml   Configured symbol row in settings
JS/
  providers.js           Provider abstraction + Stooq implementation
Support/
  setup-symlink.sh       One-time symlink into DMS plugins directory
```

## Quick start

```bash
git clone <repo-url> ~/Documents/My\ Repos/DMS-Markets-Plugin
chmod +x Support/setup-symlink.sh
Support/setup-symlink.sh
dms restart
```

Then open **DMS Settings → Plugins → Markets** to add symbols.

## Requirements

- DMS ≥ 1.2.0 (Quickshell-based plugin system)
- `curl` for data fetching
- Internet access to `stooq.com`

## Data source

All market data is provided by [Stooq](https://stooq.com) via their public CSV endpoints. No API key required.

| Endpoint | Purpose |
|----------|---------|
| `/q/l/?s=SYMBOL&i=INTERVAL` | Latest candle (price) |
| `/q/d/l/?s=SYMBOL&i=INTERVAL` | Historical data (chart) |
| `/cmp/?q=QUERY` | Symbol search / autocomplete |

## License

MIT
