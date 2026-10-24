// SymbolSummary.js - Popup counts from tracked symbols and their already displayed price changes.
.pragma library

// Count declines and sum available percentage changes; omit the summary until a valid price change is available.
function detailsText(symbols, priceData) {
    if (symbols.length === 0) return "Add symbols in Settings";
    let reported = 0;
    let declining = 0;
    let totalChangePercent = 0;
    for (let symbol of symbols) {
        let price = priceData[symbol.uid];
        if (!price || !Number.isFinite(price.close) || price.close <= 0 || !Number.isFinite(price.change)) continue;
        reported++;
        if (price.change < 0) declining++;
        if (Number.isFinite(price.changePercent)) totalChangePercent += price.changePercent;
    }
    let summary = symbols.length + " symbol" + (symbols.length !== 1 ? "s" : "") + " tracked";
    let total = Number(totalChangePercent.toFixed(2));
    let decliningPercent = Math.round((100 * declining) / symbols.length);
    if (reported === 0) return summary;
    return `${summary} (${decliningPercent}% of them down, ${total > 0 ? "+" : ""}${total}% in total)`;
}
