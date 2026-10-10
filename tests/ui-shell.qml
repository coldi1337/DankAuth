import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Services
import qs.DankCommon.Common as DC
import "testplugin"
import "Common/StockThemes.js" as StockThemes

ShellRoot {
    id: root
    Component.onCompleted: { DC.Style.theme = Theme; DC.Style.settings = SettingsData; SessionData.locale = "de"; DC.I18n.backend = I18n; I18n.registerPluginTranslations("enteAuth", root.germanTable); }
    readonly property var germanTable: JSON.parse(Quickshell.env("ENTE_QA_TRANSLATIONS"))
    property var originalTheme: Theme.currentThemeData
    property bool promo: false
    property int previewWidth: 476
    property string startupResult: ""
    property string captureStatus: ""
    property var preservedCard: null
    property real preservedScroll: 0
    property real fullPanelHeight: 0
    EnteService {
        id: vault
        pluginId: "enteAuth"
        pluginData: ({demoMode: true})
        function loadPluginData() { pluginData = {demoMode: true}; }
    }
    FloatingWindow {
        id: window
        visible: true
        title: "DankAuth layout verification"
        implicitWidth: root.promo ? 1280 : 900
        implicitHeight: root.promo ? 720 : 602
        color: Theme.surface
        PromoBoard { id: promoBoard; width: 1280; height: 720; visible: root.promo; service: vault }
        Item { visible: !root.promo; width: root.previewWidth; height: 602; AuthView { id: view; service: vault; compact: true } }
    }
    function findItem(item, name) {
        const pending = [item];
        while (pending.length) {
            const current = pending.pop();
            if (!current) continue;
            if (current.objectName === name) return current;
            if (current.children) for (let i = 0; i < current.children.length; i++) pending.push(current.children[i]);
        }
        return null;
    }
    IpcHandler {
        target: "test"
        function check(): string {
            const grid = root.findItem(view, "codeGrid");
            if (vault.tags.length !== 2) return "FAIL tag chips";
            if (!grid || grid.count !== 4 || grid.width <= 0 || grid.height <= 0) return "FAIL grid";
            const names = ["BarWidget.qml", "Settings.qml", "StartupCheck.qml"];
            for (const name of names) {
                const component = Qt.createComponent("testplugin/" + name);
                if (component.status !== Component.Ready) return "FAIL " + component.errorString();
                const item = component.createObject(root, {});
                if (!item) return "FAIL instantiate " + name;
                item.destroy();
            }
            return "PASS";
        }
        function startup(): string {
            const component = Qt.createComponent("testplugin/StartupCheck.qml");
            const probe = component.createObject(root);
            root.startupResult = "pending";
            probe.check(result => { root.startupResult = result ? JSON.stringify(result) : "PASS"; probe.destroy(); });
            return "pending";
        }
        function startupStatus(): string { return root.startupResult; }
        function clicks(): string {
            PluginService.pluginDaemonInstances = {enteAuth: vault};
            const component = Qt.createComponent("testplugin/BarWidget.qml");
            const widget = component.createObject(root, {pluginId: "enteAuth"});
            if (!widget) return "FAIL widget";
            vault.close(); widget.pillClickAction();
            if (!vault.popoutOpen || vault.windowOpen) return "FAIL left click";
            widget.pillClickAction();
            if (vault.popoutOpen || vault.windowOpen) return "FAIL left toggle";
            widget.pillRightClickAction();
            if (!vault.windowOpen || vault.popoutOpen) return "FAIL right click";
            vault.close(); widget.destroy();
            return "PASS";
        }
        function beginOptimizations(): string {
            vault.openWindow(); view.focusSearch();
            const grid = root.findItem(view, "codeGrid");
            root.preservedCard = grid.itemAtIndex(0); root.preservedScroll = grid.contentY;
            root.fullPanelHeight = vault.preferredPopupHeight;
            if (!root.preservedCard) return "FAIL missing card";
            view.navigate({key: Qt.Key_Down, accepted: false});
            if (view.selectedId !== vault.visibleRows[0].id) return "FAIL first selection";
            view.navigate({key: Qt.Key_Down, accepted: false});
            if (view.selectedId !== vault.visibleRows[1].id) return "FAIL arrow selection";
            vault.applyCodeUpdates([{id: vault.visibleRows[0].id, otp: "123456", expiresAt: Date.now() + 30000, invalid: false}]);
            vault.copiedId = vault.visibleRows[0].id;
            return "PASS";
        }
        function endOptimizations(): string {
            const grid = root.findItem(view, "codeGrid");
            if (grid.itemAtIndex(0) !== root.preservedCard || grid.contentY !== root.preservedScroll) return "FAIL model reset";
            if (vault.visibleModel.get(0).row.otp !== "123456") return "FAIL code update";
            if (view.selectedId !== vault.visibleRows[1].id) return "FAIL lost selection";
            vault.query = "infrastructure";
            if (!(vault.preferredPopupHeight < root.fullPanelHeight)) return "FAIL panel height";
            vault.query = ""; vault.copiedId = ""; vault.close(); vault.loadDemo();
            return "PASS";
        }
        function locale(name: string): void {
            SessionData.locale = name;
            if (name === "de") I18n.registerPluginTranslations("enteAuth", root.germanTable);
            else {
                I18n.unregisterPluginTranslations("enteAuth");
                // The private fixture has no PluginService locale loader. Reset
                // the common catalog explicitly to the English source fallback.
                I18n.translationsLoaded = false;
                I18n.commonTranslationsLoaded = false;
            }
        }
        function translatedSearch(): string { return root.findItem(view, "searchField").placeholderText; }
        function width(value: int): void { root.previewWidth = value; }
        function theme(name: string): void {
            if (name === "original") { Theme.currentTheme = "custom"; Theme.customThemeData = JSON.parse(Quickshell.env("ENTE_QA_THEME")).dark; Theme.isLightMode = false; }
            else { Theme.currentTheme = name === "light" ? "blue" : "purple"; Theme.isLightMode = name === "light"; }
        }
        function filter(name: string): string {
            vault.tag = name;
            return String(vault.visibleRows.length);
        }
        function query(value: string): string { vault.query = value; return String(vault.visibleRows.length); }
        function login(step: string): void { vault.query = ""; vault.tag = ""; vault.state = {step: step, unlocked: false, email: "demo@example.org", hasAccount: step === "locked"}; }
        function demo(): void { vault.loadDemo(); }
        function capture(name: string): string {
            root.captureStatus = "pending";
            view.grabToImage(result => { root.captureStatus = result.saveToFile(Quickshell.env("ENTE_QA_OUTPUT") + "/" + name + ".png") ? "saved" : "failed"; });
            return "pending";
        }
        function logo(): string {
            const component = Qt.createComponent("testplugin/AuthLogo.qml");
            if (component.status !== Component.Ready) return "failed";
            const item = component.createObject(window.contentItem, {width: 96, height: 96, color: Theme.primary});
            root.captureStatus = "pending";
            Qt.callLater(() => item.grabToImage(result => {
                root.captureStatus = result.saveToFile(Quickshell.env("ENTE_QA_OUTPUT") + "/dankauth-logo.png") ? "saved" : "failed";
                item.destroy();
            }));
            return "pending";
        }
        function bar(orientation: string, locked: string): string {
            PluginService.pluginDaemonInstances = {enteAuth: vault};
            if (locked === "yes") vault.state = {step: "locked", unlocked: false, hasAccount: true};
            else vault.loadDemo();
            const component = Qt.createComponent("testplugin/BarWidget.qml");
            const widget = component.createObject(window.contentItem, {pluginId: "enteAuth", axis: {isVertical: orientation === "vertical", edge: orientation === "vertical" ? "left" : "top"}});
            root.captureStatus = "pending";
            Qt.callLater(() => widget.grabToImage(result => {
                root.captureStatus = result.saveToFile(Quickshell.env("ENTE_QA_OUTPUT") + "/bar-" + orientation + "-" + locked + ".png") ? "saved" : "failed";
                widget.destroy();
            }));
            return "pending";
        }
        function preview(language: string): string {
            root.promo = true; vault.loadDemo();
            locale(language); theme("dark"); Theme.fontScale = 1;
            root.captureStatus = "pending";
            Qt.callLater(() => promoBoard.grabToImage(result => {
                root.captureStatus = result.saveToFile(Quickshell.env("ENTE_QA_OUTPUT") + "/preview-" + language + ".png") ? "saved" : "failed";
            }));
            return "pending";
        }
        function captured(): string { return root.captureStatus; }
        function layout(): string { return JSON.stringify({columns: view.columns, width: view.width, height: view.height, tags: vault.tags, primary: String(Theme.primary), surface: String(Theme.surface)}); }
    }
}
