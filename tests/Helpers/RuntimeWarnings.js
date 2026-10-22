// RuntimeWarnings.js - keep runtime diagnostics fatal, except explicitly declared FileView fault-injection output.
// Quickshell's file-open failure prints even with printErrors:false; declarations match one exact path and a limit.
function unexpectedWarnings(output) {
    const expectedWrites = new Map();
    for (const line of output.split("\n")) {
        const marker = /T:EXPECTED-FILE-WRITE-WARNING (\{.*\})/.exec(line);
        if (!marker) continue;
        const declaration = JSON.parse(marker[1]);
        if (
            typeof declaration.path === "string" &&
            Number.isInteger(declaration.maxCount) &&
            declaration.maxCount > 0 &&
            declaration.maxCount <= 10
        )
            expectedWrites.set(declaration.path, declaration.maxCount);
    }
    return output.split("\n").filter((line) => {
        if (
            !/^\s*(WARN|ERROR)\b/.test(line) ||
            /T:|qml: (ok  |LOG )|WAYLAND|QT_QPA_PLATFORM|If you are actually|--- WARNING ---/.test(line)
        )
            return false;
        if (
            /^\s*WARN\b.*QML FileView at file:\/\/.*\/src\/QML\/Services\/MarketCache\.qml\[\d+:\d+\]: Write of /.test(
                line
            )
        ) {
            for (const [filePath, remaining] of expectedWrites) {
                if (remaining > 0 && line.endsWith(`Write of ${filePath} failed: Unknown error when opening file.`)) {
                    expectedWrites.set(filePath, remaining - 1);
                    return false;
                }
            }
        }
        return true;
    });
}
module.exports = { unexpectedWarnings };
