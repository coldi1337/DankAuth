import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Common
import qs.Services
import qs.Widgets
import qs.Modules.Plugins

PluginComponent {
    id: root
    property var popoutService: null
    property var state: ({step: "email", unlocked: false})
    readonly property string step: state.step || "email"
    readonly property bool unlocked: !!state.unlocked
    readonly property bool surfaceOpen: popout.shouldBeVisible || app.visible
    readonly property bool popoutOpen: popout.shouldBeVisible
    readonly property bool windowOpen: app.visible
    property var rows: []
    property double snapshotAt: 0
    property string copiedId: ""
    property double copiedAt: 0
    property bool updatingCodes: false
    property bool editingTags: false
    readonly property real preferredPopupHeight: Math.round(Math.min((popout.screen?.height || 900) - popout.storedBarThickness - Theme.spacingL * 2, root.unlocked ? Theme.fontSizeMedium * 15 + Math.max(1, Math.min(4, root.visibleRows.length)) * (Theme.fontSizeMedium * 9.5 + Theme.spacingS) + (root.errorText ? Theme.fontSizeMedium * 5 : 0) + (root.editingTags ? Theme.fontSizeMedium * 9 : 0) : Theme.fontSizeMedium * 43))
    readonly property bool closeAfterCopy: pluginData.closeAfterCopy ?? false
    property alias visibleModel: entries
    ListModel { id: entries; dynamicRoles: true }
    property string query: ""
    property string tag: ""
    property bool favoritesOnly: false
    property bool busy: false
    property bool ready: false
    property string errorText: ""
    property var pending: ({})
    property int serial: 0
    property int generation: 0
    property bool passkeyPolling: false
    readonly property bool demo: pluginData.demoMode ?? false
    readonly property int lockMinutes: pluginData.lockMinutes ?? 5
    readonly property int syncMinutes: pluginData.syncMinutes ?? 5
    readonly property string accountsUrl: pluginData.accountsUrl || ""
    readonly property var tags: rows.reduce((all, row) => { (row.tags || []).forEach(tag => { if (!all.includes(tag)) all.push(tag); }); return all; }, []).sort()
    function isFavorite(row) { return !!row.pinned; }
    readonly property var visibleRows: rows.filter(row =>
        (!favoritesOnly || isFavorite(row)) && (!tag || row.tags.includes(tag)) &&
        (!query || (row.issuer + " " + row.account + " " + row.tags.join(" ")).toLowerCase().includes(query.toLowerCase()))
    ).sort((a, b) => Number(isFavorite(b)) - Number(isFavorite(a)) || a.issuer.localeCompare(b.issuer));
    function reconcile() {
        const next = visibleRows;
        for (let i = 0; i < next.length; i++) {
            if (i < entries.count && entries.get(i).row.id === next[i].id) entries.setProperty(i, "row", next[i]);
            else {
                let found = -1;
                for (let j = i + 1; j < entries.count; j++) if (entries.get(j).row.id === next[i].id) { found = j; break; }
                if (found >= 0) { entries.move(found, i, 1); entries.setProperty(i, "row", next[i]); }
                else entries.insert(i, {row: next[i]});
            }
        }
        if (entries.count > next.length) entries.remove(next.length, entries.count - next.length);
    }
    onVisibleRowsChanged: reconcile()
    function favorite(row) { operate("metadata", {id: row.id, pinned: !row.pinned}); }
    function saveTags(row, text) { operate("metadata", {id: row.id, tags: text.split(",").map(value => value.trim()).filter(Boolean)}); }
    function scheduleCodes() {
        codeTimer.stop();
        if (!surfaceOpen || !unlocked || demo || !rows.length) return;
        const expiry = rows.filter(row => row.expiresAt > 0).reduce((next, row) => Math.min(next, row.expiresAt), Infinity);
        if (isFinite(expiry)) { codeTimer.interval = Math.max(150, expiry - Date.now() + 30); codeTimer.start(); }
    }
    function applyCodeUpdates(updates) {
        for (const update of updates) {
            const row = rows.find(row => row.id === update.id);
            if (row) Object.assign(row, update);
            for (let i = 0; i < entries.count; i++) if (entries.get(i).row.id === update.id) entries.setProperty(i, "row", Object.assign({}, entries.get(i).row, update));
        }
    }
    function updateCodes() {
        if (updatingCodes || busy || !surfaceOpen || !unlocked || demo) { scheduleCodes(); return; }
        updatingCodes = true;
        if (!request("otp_updates", {ids: rows.filter(row => row.expiresAt > 0 && row.expiresAt <= Date.now() + 100).map(row => row.id)}, result => {
            updatingCodes = false;
            if (result.ok && unlocked) {
                applyCodeUpdates(result.rows || []);
            }
            scheduleCodes();
        })) updatingCodes = false;
    }
    function acceptState(value) {
        if (!value) return;
        state = value;
        if (!unlocked) { rows = []; snapshotAt = 0; copiedId = ""; updatingCodes = false; codeTimer.stop(); }
        if (!state.passkey) passkeyPolling = false;
    }
    function message(code) {
        const messages = {
            auth_failed: I18n.trFor("enteAuth", "Authentication failed. Check your password or verification code."),
            sync_failed: I18n.trFor("enteAuth", "Sync failed. Cached codes remain available; try again."),
            request_failed: I18n.trFor("enteAuth", "Could not complete the request. Check your connection and server settings."),
            clipboard_failed: I18n.trFor("enteAuth", "Could not copy the code. Check the DMS clipboard service."),
            storage_failed: I18n.trFor("enteAuth", "The saved vault could not be read."),
            busy: I18n.trFor("enteAuth", "Another operation is still running.")
        };
        return messages[code] || I18n.trFor("enteAuth", "The service response could not be read.");
    }

    function request(action, params, callback) {
        if (!bridge.running || !ready) { errorText = I18n.trFor("enteAuth", "Service unavailable. Run scripts/setup and reload the plugin."); return false; }
        const id = String(++serial);
        pending = Object.assign({}, pending, {[id]: {callback: callback || (() => {}), started: Date.now(), generation: generation}});
        bridge.write(JSON.stringify({requestId: id, action: action, params: params || {}}) + "\n");
        return true;
    }
    function configure() { request("configure", {lockMinutes: lockMinutes, accountsUrl: accountsUrl}); }
    function operate(action, params, userAction = true) {
        if (busy || demo) return;
        busy = true; errorText = ""; if (userAction) touch();
        if (!request(action, params, result => {
            busy = false;
            if (!result.ok) { if (result.error !== "cancelled") errorText = message(result.error); if (unlocked) refresh(); return; }
            if (result.url) { Qt.openUrlExternally(result.url); passkeyPolling = true; }
            if (result.state?.warning) errorText = message(result.state.warning);
            if (unlocked && action === "password" && state.syncStatus === "cached") operate("sync", {}, false);
            else if (unlocked) refresh();
        })) busy = false;
    }
    function refresh() {
        if (!unlocked || busy || demo || !surfaceOpen) return;
        request("list", {}, result => { if (result.ok && unlocked) { rows = result.rows || []; snapshotAt = Date.now(); scheduleCodes(); } });
    }
    function touch() { if (ready && !demo) request("touch", {}); }
    function lock() {
        generation++; pending = {}; busy = false; rows = []; query = ""; tag = ""; passkeyPolling = false;
        acceptState(Object.assign({}, state, {unlocked: false, step: state.hasAccount ? "locked" : "email"}));
        if (!demo) request("lock", {}, result => acceptState(result.state));
    }
    function copy(row) {
        if (demo || !unlocked) return;
        request("copy", {id: row.id}, result => {
            if (result.ok) { copiedId = row.id; copiedAt = Date.now(); copiedTimer.restart(); if (closeAfterCopy && popoutOpen) closeTimer.restart(); }
            else errorText = message(result.error);
        });
    }
    function setAnchor(x, y, width, section, screen, edge, thickness, spacing, config) { popout.setTriggerPosition(x, y, width, section, screen, edge, thickness, spacing, config); }
    function toggle() { if (!IdleService.isShellLocked) { app.visible = false; popout.toggle(); Qt.callLater(refresh); } }
    function openWindow() { if (!IdleService.isShellLocked) { popout.close(); app.visible = true; Qt.callLater(refresh); } }
    function close() { popout.close(); app.visible = false; }
    function loadDemo() {
        generation++; busy = false; pending = {}; ready = false; errorText = "";
        state = {step: "unlocked", unlocked: true, email: "demo@example.org", hasAccount: false, syncedAt: Date.now()};
        rows = [
            {id: "github", issuer: "GitHub", account: "coldi@example.org", tags: ["Development"], pinned: true, type: "totp", otp: "482193", period: 30, remaining: 24},
            {id: "ente", issuer: "Ente", account: "personal@example.org", tags: ["Personal"], pinned: false, type: "totp", otp: "706284", period: 30, remaining: 24},
            {id: "cloud", issuer: "Cloudflare", account: "infrastructure@example.org", tags: ["Development"], pinned: false, type: "totp", otp: "315907", period: 30, remaining: 24},
            {id: "steam", issuer: "Steam", account: "coldi", tags: ["Personal"], pinned: false, type: "steam", otp: "7K9QX", period: 30, remaining: 24}
        ]; snapshotAt = Date.now();
    }
    onDemoChanged: {
        generation++; pending = {}; rows = []; ready = false; busy = false; passkeyPolling = false;
        if (demo) { bridge.running = false; loadDemo(); }
        else { state = {step: "email", unlocked: false}; bridge.running = true; }
    }
    onLockMinutesChanged: { if (ready) configure(); }
    onAccountsUrlChanged: { if (ready) configure(); }
    onSurfaceOpenChanged: { if (surfaceOpen) { touch(); refresh(); } else codeTimer.stop(); }
    Component.onCompleted: { if (demo) loadDemo(); }
    Connections {
        target: IdleService
        function onIsShellLockedChanged() { if (IdleService.isShellLocked) { root.lock(); root.close(); } }
    }
    Process {
        id: bridge
        command: ["sh", Qt.resolvedUrl("scripts/run-bridge").toString().replace("file://", "")]
        running: !root.demo
        stdinEnabled: true
        stdout: SplitParser {
            onRead: line => {
                try {
                    const result = JSON.parse(line);
                    if (result.event === "ready") { root.ready = true; root.acceptState(result.state); root.configure(); return; }
                    if (result.event === "locked") { root.generation++; root.pending = {}; root.busy = false; root.query = ""; root.tag = ""; root.acceptState(result.state); return; }
                    if (result.event === "error") { root.errorText = root.message(result.error); return; }
                    const entry = root.pending[result.requestId];
                    const next = Object.assign({}, root.pending); delete next[result.requestId]; root.pending = next;
                    if (entry && entry.generation === root.generation) { root.acceptState(result.state); entry.callback(result); }
                } catch (error) { root.errorText = I18n.trFor("enteAuth", "The service response could not be read."); }
            }
        }
        stderr: StdioCollector {}
        onExited: {
            root.ready = false; root.generation++; root.pending = {}; root.busy = false; root.passkeyPolling = false;
            if (!root.demo) { root.rows = []; root.state = {step: "email", unlocked: false}; root.errorText = I18n.trFor("enteAuth", "Service unavailable. Run scripts/setup and reload the plugin."); }
        }
    }
    Timer { id: codeTimer; onTriggered: root.updateCodes() }
    Timer { id: copiedTimer; interval: 1600; onTriggered: root.copiedId = "" }
    Timer { id: closeTimer; interval: 350; onTriggered: { if (root.popoutOpen && root.unlocked) popout.close(); } }
    Timer { interval: root.syncMinutes * 60000; running: root.unlocked && !root.demo; repeat: true; onTriggered: root.operate("sync", {}, false) }
    Timer { interval: 2000; running: root.passkeyPolling && !root.busy && !root.demo; repeat: true; onTriggered: root.operate("poll_passkey", {}, false) }
    Timer {
        interval: 1000; running: Object.keys(root.pending).length > 0; repeat: true
        onTriggered: {
            for (const id of Object.keys(root.pending)) {
                const entry = root.pending[id];
                if (Date.now() - entry.started < 45000) continue;
                const next = Object.assign({}, root.pending); delete next[id]; root.pending = next; entry.callback({ok: false, error: "request_failed"});
            }
        }
    }
    DankPopout {
        id: popout
        popupWidth: Math.round(Theme.fontSizeMedium * 34)
        popupHeight: root.preferredPopupHeight
        contentHandlesKeys: true
        backgroundInteractive: true
        onBackgroundClicked: close()
        customKeyboardFocus: WlrKeyboardFocus.OnDemand
        content: Component {
            AuthView { service: root; compact: true; onExpandRequested: root.openWindow(); onCloseRequested: popout.close() }
        }
    }
    DankFloatingWindow {
        id: app
        title: "DankAuth"
        surfaceColor: Qt.rgba(Theme.surface.r, Theme.surface.g, Theme.surface.b, 1)
        visible: false
        implicitWidth: Math.round(Theme.fontSizeMedium * 55)
        implicitHeight: Math.round(Theme.fontSizeMedium * 46)
        minimumSize: Qt.size(360, 420)
        onClosed: visible = false
        AuthView { service: root; compact: false; onCloseRequested: root.close() }
    }
    IpcHandler {
        target: "enteAuth"
        function open(): void { root.openWindow(); }
        function close(): void { root.close(); }
        function lock(): void { root.lock(); }
        function sync(): void { root.operate("sync", {}); }
        function status(): string { return JSON.stringify({ready: root.ready, step: root.step, unlocked: root.unlocked, count: root.rows.length, error: root.errorText}); }
        function addToBar(barId: string): string {
            const config = SettingsData.getBarConfig(barId);
            if (!config) return "BAR_NOT_FOUND";
            const widgets = (config.rightWidgets || []).slice();
            if (widgets.some(widget => (typeof widget === "string" ? widget : widget.id) === "enteAuth")) return "ALREADY_PRESENT";
            const index = widgets.findIndex(widget => (typeof widget === "string" ? widget : widget.id) === "bitwarden");
            widgets.splice(index < 0 ? widgets.length : index + 1, 0, {id: "enteAuth", enabled: true});
            SettingsData.updateBarConfig(barId, {rightWidgets: widgets});
            return "ADDED";
        }
    }
}
