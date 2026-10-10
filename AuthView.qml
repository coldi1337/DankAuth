import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic as Controls
import qs.Common
import qs.Widgets

Item {
    id: root
    anchors.fill: parent
    required property var service
    property bool compact: true
    property bool logoutConfirm: false
    property double now: Date.now()
    property string selectedId: ""
    property var editingRow: null
    onEditingRowChanged: service.editingTags = !!editingRow
    function focusSearch() { if (visible && service.surfaceOpen && service.unlocked) search.forceActiveFocus(); }
    function navigate(event) {
        if (!service.unlocked || editingRow || event.modifiers) return;
        let delta = event.key === Qt.Key_Down ? columns : event.key === Qt.Key_Up ? -columns : event.key === Qt.Key_Right ? 1 : event.key === Qt.Key_Left ? -1 : 0;
        if (delta && (!(search.getActiveFocus()) || Math.abs(delta) === columns && (event.key === Qt.Key_Down || event.key === Qt.Key_Up))) {
            const current = service.visibleRows.findIndex(row => row.id === selectedId);
            const index = Math.max(0, Math.min(service.visibleRows.length - 1, current < 0 ? (delta > 0 ? 0 : service.visibleRows.length - 1) : current + delta));
            if (index >= 0 && service.visibleRows.length) { selectedId = service.visibleRows[index].id; grid.positionViewAtIndex(index, GridView.Contain); grid.forceActiveFocus(); }
            event.accepted = true; service.touch();
        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            const row = service.visibleRows.find(row => row.id === selectedId) || service.visibleRows[0];
            if (row) service.copy(row); event.accepted = true;
        }
    }
    onVisibleChanged: { if (!visible) editingRow = null; Qt.callLater(focusSearch); }
    Component.onCompleted: Qt.callLater(focusSearch)
    readonly property int columns: width >= Theme.fontSizeMedium * 48 ? 2 : 1
    readonly property bool passwordStep: ["locked", "password", "password-decrypt"].includes(service.step)
    signal expandRequested()
    signal closeRequested()
    function remaining(row) {
        if (service.demo) return Math.max(1, row.remaining - Math.floor((now - service.snapshotAt) / 1000) % row.period);
        return Math.max(0, Math.ceil((row.expiresAt - now) / 1000));
    }
    function submit() {
        if (service.busy || service.demo) return;
        if (service.step === "email") service.operate("login", {email: email.text, server: service.pluginData.serverUrl || ""});
        else if (root.passwordStep) { service.operate("password", {password: credential.text}); credential.clear(); }
        else if (["email-code", "two-factor"].includes(service.step)) { service.operate("verify", {code: credential.text}); credential.clear(); }
    }
    focus: true
    Keys.onEscapePressed: { if (editingRow) { editingRow = null; focusSearch(); } else if (logoutConfirm) logoutConfirm = false; else closeRequested(); }
    Keys.onPressed: event => {
        navigate(event);
        if (event.modifiers === Qt.ControlModifier && event.key === Qt.Key_L) { service.lock(); event.accepted = true; }
        if (event.modifiers === Qt.ControlModifier && event.key === Qt.Key_F && service.unlocked) { search.forceActiveFocus(); event.accepted = true; }
    }
    Connections {
        target: root.service
        function onStepChanged() { credential.clear(); root.logoutConfirm = false; root.editingRow = null; Qt.callLater(root.focusSearch); }
        function onSurfaceOpenChanged() { Qt.callLater(root.focusSearch); }
    }
    Timer { interval: 1000; running: root.visible && root.service.surfaceOpen && root.service.unlocked; repeat: true; onTriggered: root.now = Date.now() }
    Rectangle { anchors.fill: parent; color: Theme.surface; z: -1 }
    component Label: StyledText { textFormat: Text.PlainText; color: Theme.surfaceText }
    component Action: DankActionButton { circular: false; iconColor: Theme.surfaceText; Accessible.name: tooltipText }
    component Chip: DankButton {
        property bool selected: false
        buttonHeight: Math.round(Theme.fontSizeSmall * 2.8)
        horizontalPadding: Theme.spacingM
        backgroundColor: selected ? Theme.primary : Theme.surfaceContainerHigh
        textColor: selected ? Theme.primaryText : Theme.surfaceText
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Theme.spacingM
        spacing: Theme.spacingM
        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.spacingS
            Rectangle {
                Layout.preferredWidth: Theme.iconSize * 2
                Layout.preferredHeight: width
                radius: Theme.cornerRadius
                color: Theme.withAlpha(Theme.primary, 0.12)
                Loader { anchors.centerIn: parent; width: Theme.iconSize * 1.25; height: width; source: Qt.resolvedUrl("AuthLogo.qml"); onLoaded: item.color = Qt.binding(() => Theme.primary) }
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: Theme.spacingXS
                Label { text: "DankAuth"; font.pixelSize: Theme.fontSizeXLarge; font.weight: Font.DemiBold }
                Label {
                    Layout.fillWidth: true
                    text: service.demo ? I18n.trFor("enteAuth", "Demo · sample entries") : service.state.email || I18n.trFor("enteAuth", "Your codes, in your desktop")
                    color: Theme.surfaceVariantText; font.pixelSize: Theme.fontSizeSmall; elide: Text.ElideRight
                }
            }
            Action { visible: root.compact; iconName: "open_in_full"; tooltipText: I18n.trFor("enteAuth", "Open window"); onClicked: root.expandRequested() }
            Action { iconName: "close"; tooltipText: I18n.trFor("enteAuth", "Close"); onClicked: root.closeRequested() }
        }
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: notice.implicitHeight + Theme.spacingM * 2
            visible: !!service.errorText
            radius: Theme.cornerRadius
            color: Theme.withAlpha(Theme.error, 0.12)
            Label { id: notice; anchors.fill: parent; anchors.margins: Theme.spacingM; wrapMode: Text.WordWrap; text: service.errorText; color: Theme.error; font.pixelSize: Theme.fontSizeSmall }
        }
        // Search and filters follow Ente's familiar list; all styling comes from DMS.
        RowLayout {
            visible: service.unlocked
            Layout.fillWidth: true
            DankTextField {
                id: search
                objectName: "searchField"
                Layout.fillWidth: true
                leftIconName: "search"
                placeholderText: I18n.trFor("enteAuth", "Search accounts or tags")
                placeholderColor: Theme.surfaceVariantText
                showClearButton: true
                text: service.query
                onTextEdited: { service.query = text; root.selectedId = ""; service.touch(); }
                ignoreUpDownKeys: true
                keyForwardTargets: [root]
                onAccepted: root.navigate({key: Qt.Key_Return, accepted: false})
            }
            Action { iconName: "sync"; tooltipText: I18n.trFor("enteAuth", "Sync now"); enabled: !service.busy && !service.demo; onClicked: service.operate("sync", {}) }
            Action { iconName: "lock"; tooltipText: I18n.trFor("enteAuth", "Lock"); enabled: !service.demo; onClicked: service.lock() }
        }
        Controls.ScrollView {
            visible: service.unlocked
            Layout.fillWidth: true
            Layout.preferredHeight: filters.implicitHeight
            contentWidth: filters.implicitWidth
            contentHeight: filters.implicitHeight
            Controls.ScrollBar.horizontal.policy: Controls.ScrollBar.AlwaysOff
            Controls.ScrollBar.vertical.policy: Controls.ScrollBar.AlwaysOff
            Row {
                id: filters
                spacing: Theme.spacingS
                Chip { text: I18n.trFor("enteAuth", "All"); selected: !service.favoritesOnly && !service.tag; onClicked: { service.favoritesOnly = false; service.tag = ""; service.touch(); } }
                Chip { text: I18n.trFor("enteAuth", "Favorites"); iconName: "star"; selected: service.favoritesOnly; onClicked: { service.favoritesOnly = !service.favoritesOnly; service.touch(); } }
                Repeater {
                    model: service.tags
                    Chip { required property string modelData; text: modelData; selected: service.tag === modelData; onClicked: { service.tag = selected ? "" : modelData; service.touch(); } }
                }
            }
        }
        ColumnLayout {
            visible: !!root.editingRow && service.unlocked
            Layout.fillWidth: true
            Label { Layout.fillWidth: true; text: I18n.trFor("enteAuth", "Edit tags") + " · " + (root.editingRow?.issuer || ""); elide: Text.ElideRight }
            DankTextField { id: tagEditor; Layout.fillWidth: true; placeholderText: I18n.trFor("enteAuth", "Tags separated by commas"); maximumLength: 2000 }
            RowLayout {
                DankButton { text: I18n.trFor("enteAuth", "Save"); enabled: !service.busy; onClicked: { service.saveTags(root.editingRow, tagEditor.text); root.editingRow = null; root.focusSearch(); } }
                DankButton { text: I18n.trFor("enteAuth", "Cancel"); onClicked: { root.editingRow = null; root.focusSearch(); } }
            }
        }
        GridView {
            id: grid
            objectName: "codeGrid"
            visible: service.unlocked
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            cellWidth: width / root.columns
            cellHeight: Theme.fontSizeMedium * 9.5 + Theme.spacingS
            model: service.visibleModel
            boundsBehavior: Flickable.StopAtBounds
            Controls.ScrollBar.vertical: Controls.ScrollBar {}
            delegate: Item {
                id: delegateRoot
                required property var row
                readonly property var modelData: row
                required property int index
                width: grid.cellWidth
                height: grid.cellHeight
                readonly property int remaining: root.remaining(modelData)
                readonly property string otp: remaining > 0 ? modelData.otp : ""
                Rectangle {
                    anchors.fill: parent
                    anchors.rightMargin: root.columns > 1 && delegateRoot.index % root.columns === 0 ? Theme.spacingS : 0
                    anchors.bottomMargin: Theme.spacingS
                    color: copyArea.containsMouse ? Theme.surfaceContainerHighest : Theme.surfaceContainerHigh
                    radius: Theme.cornerRadius
                    border.color: copyArea.activeFocus || root.selectedId === delegateRoot.modelData.id ? Theme.primary : Theme.outline
                    border.width: copyArea.activeFocus || root.selectedId === delegateRoot.modelData.id ? 2 : 1
                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: Theme.spacingM
                        spacing: Theme.spacingS
                        RowLayout {
                            Layout.fillWidth: true
                            Rectangle {
                                Layout.preferredWidth: Theme.iconSize * 1.6
                                Layout.preferredHeight: width
                                radius: Theme.cornerRadius
                                color: Theme.withAlpha(Theme.primary, 0.12)
                                Label { anchors.centerIn: parent; text: delegateRoot.modelData.issuer.slice(0, 2).toUpperCase(); color: Theme.primary; font.weight: Font.DemiBold }
                            }
                            ColumnLayout {
                                Layout.fillWidth: true; spacing: Theme.spacingXS
                                Label { Layout.fillWidth: true; text: delegateRoot.modelData.issuer; font.weight: Font.DemiBold; elide: Text.ElideRight }
                                Label { Layout.fillWidth: true; text: delegateRoot.modelData.account; color: Theme.surfaceVariantText; font.pixelSize: Theme.fontSizeSmall; elide: Text.ElideRight }
                            }
                            Action { iconName: service.isFavorite(delegateRoot.modelData) ? "star" : "star_outline"; iconColor: service.isFavorite(delegateRoot.modelData) ? Theme.primary : Theme.surfaceVariantText; tooltipText: I18n.trFor("enteAuth", "Favorite"); enabled: !service.busy && !service.demo; onClicked: service.favorite(delegateRoot.modelData) }
                        }
                        Item {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            MouseArea {
                                id: copyArea
                                anchors.fill: parent
                                hoverEnabled: true
                                activeFocusOnTab: true
                                enabled: !service.demo && !!delegateRoot.otp && !delegateRoot.modelData.invalid
                                cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                                onClicked: { root.selectedId = delegateRoot.modelData.id; service.copy(delegateRoot.modelData); }
                                Keys.onReturnPressed: service.copy(delegateRoot.modelData)
                                Keys.onSpacePressed: service.copy(delegateRoot.modelData)
                                Accessible.name: I18n.trFor("enteAuth", "Copy code") + " " + delegateRoot.modelData.issuer
                                Accessible.role: Accessible.Button
                            }
                            Label {
                                anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
                                anchors.right: countdown.left; anchors.rightMargin: Theme.spacingS
                                text: service.copiedId === delegateRoot.modelData.id ? "✓ " + I18n.trFor("enteAuth", "Code copied") : delegateRoot.modelData.type === "hotp" ? I18n.trFor("enteAuth", "Use Ente for HOTP") : delegateRoot.modelData.invalid ? I18n.trFor("enteAuth", "Invalid code") : delegateRoot.otp.length === 6 ? delegateRoot.otp.slice(0, 3) + " " + delegateRoot.otp.slice(3) : delegateRoot.otp || "··· ···"
                                font.pixelSize: delegateRoot.modelData.type === "hotp" || delegateRoot.modelData.invalid ? Theme.fontSizeSmall : Theme.fontSizeXLarge * 1.35
                                font.weight: Font.DemiBold; color: Theme.primary; elide: Text.ElideRight
                            }
                            Item {
                                id: countdown
                                anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                                width: Theme.iconSize * 1.7; height: width
                                visible: delegateRoot.modelData.type !== "hotp"
                                Canvas {
                                    anchors.fill: parent
                                    property real ratio: delegateRoot.remaining / Math.max(1, delegateRoot.modelData.period)
                                    property color accent: Theme.primary
                                    property color track: Theme.outline
                                    onRatioChanged: requestPaint()
                                    onAccentChanged: requestPaint()
                                    onTrackChanged: requestPaint()
                                    onWidthChanged: requestPaint()
                                    onPaint: {
                                        const ctx = getContext("2d"), radius = width / 2 - 3;
                                        ctx.reset(); ctx.lineWidth = 2;
                                        ctx.strokeStyle = track; ctx.beginPath(); ctx.arc(width / 2, height / 2, radius, 0, Math.PI * 2); ctx.stroke();
                                        ctx.strokeStyle = accent; ctx.beginPath(); ctx.arc(width / 2, height / 2, radius, -Math.PI / 2, -Math.PI / 2 + Math.PI * 2 * ratio); ctx.stroke();
                                    }
                                }
                                Label { anchors.centerIn: parent; text: String(delegateRoot.remaining); font.pixelSize: Theme.fontSizeSmall; color: Theme.surfaceVariantText }
                            }
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            Label { Layout.fillWidth: true; text: delegateRoot.modelData.tags.join(" · ") || delegateRoot.modelData.type.toUpperCase(); color: Theme.surfaceVariantText; font.pixelSize: Theme.fontSizeSmall; elide: Text.ElideRight }
                            Action { iconName: "edit"; tooltipText: I18n.trFor("enteAuth", "Edit tags"); enabled: !service.demo && !service.busy; onClicked: { root.editingRow = delegateRoot.modelData; tagEditor.text = delegateRoot.modelData.tags.join(", "); tagEditor.forceActiveFocus(); } }
                        }
                    }
                }
            }
            Label {
                anchors.centerIn: parent
                width: parent.width - Theme.spacingL
                visible: grid.count === 0
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                text: service.rows.length ? I18n.trFor("enteAuth", "No matching accounts") : I18n.trFor("enteAuth", "No codes yet. Sync your Ente account.")
                color: Theme.surfaceVariantText
            }
        }
        Controls.ScrollView {
            visible: !service.unlocked
            Layout.fillWidth: true; Layout.fillHeight: true
            contentWidth: availableWidth
            ColumnLayout {
                width: parent.width
                spacing: Theme.spacingM
                Label { Layout.fillWidth: true; text: service.step === "locked" ? I18n.trFor("enteAuth", "Unlock your vault") : I18n.trFor("enteAuth", "Connect to Ente Auth"); font.pixelSize: Theme.fontSizeLarge; font.weight: Font.DemiBold }
                Label {
                    Layout.fillWidth: true; wrapMode: Text.WordWrap; color: Theme.surfaceVariantText
                    text: service.step === "locked" ? I18n.trFor("enteAuth", "Enter your Ente password. Your encrypted cache also works offline.") : service.step === "email-code" ? I18n.trFor("enteAuth", "Enter the verification code sent to your email.") : service.step === "two-factor" ? I18n.trFor("enteAuth", "Enter the second-factor code for your Ente account.") : service.step === "passkey" ? I18n.trFor("enteAuth", "Verify your passkey in the browser, then return here.") : service.step === "password-decrypt" ? I18n.trFor("enteAuth", "Enter your Ente password to decrypt your codes.") : I18n.trFor("enteAuth", "Sign in with your existing Ente account. Decryption happens locally.")
                }
                DankTextField {
                    id: email
                    objectName: "emailField"
                    Layout.fillWidth: true
                    visible: service.step === "email"
                    placeholderText: I18n.trFor("enteAuth", "Email address")
                    placeholderColor: Theme.surfaceVariantText
                    leftIconName: "mail"
                    maximumLength: 320
                    enabled: !service.busy
                    onAccepted: root.submit()
                }
                DankTextField {
                    id: credential
                    objectName: "credentialField"
                    Layout.fillWidth: true
                    visible: root.passwordStep || ["email-code", "two-factor"].includes(service.step)
                    echoMode: root.passwordStep ? TextInput.Password : TextInput.Normal
                    showPasswordToggle: root.passwordStep
                    leftIconName: root.passwordStep ? "key" : "pin"
                    placeholderText: root.passwordStep ? I18n.trFor("enteAuth", "Ente password") : I18n.trFor("enteAuth", "Verification code")
                    placeholderColor: Theme.surfaceVariantText
                    maximumLength: 1024
                    enabled: !service.busy
                    onTextEdited: service.touch()
                    onAccepted: root.submit()
                }
                DankButton {
                    Layout.fillWidth: true
                    visible: service.step !== "passkey"
                    enabled: !service.busy && (service.step === "email" ? email.text.includes("@") : credential.text.length > 0)
                    text: service.busy ? I18n.trFor("enteAuth", "Please wait…") : service.step === "locked" ? I18n.trFor("enteAuth", "Unlock") : I18n.trFor("enteAuth", "Continue")
                    onClicked: root.submit()
                }
                DankButton { Layout.fillWidth: true; visible: !!service.state.passkey; enabled: !service.busy; iconName: "fingerprint"; text: I18n.trFor("enteAuth", "Use passkey in browser"); onClicked: service.operate("passkey", {}) }
                DankButton {
                    Layout.fillWidth: true; visible: service.step !== "email" && service.step !== "locked"
                    backgroundColor: Theme.surfaceContainerHigh; textColor: Theme.surfaceText
                    text: I18n.trFor("enteAuth", "Cancel sign-in"); onClicked: service.lock()
                }
                Label { Layout.fillWidth: true; wrapMode: Text.WordWrap; text: I18n.trFor("enteAuth", "Unofficial Ente client · credentials and cache are stored encrypted."); color: Theme.surfaceVariantText; font.pixelSize: Theme.fontSizeSmall }
            }
        }
        RowLayout {
            Layout.fillWidth: true
            Label {
                Layout.fillWidth: true
                text: service.demo ? I18n.trFor("enteAuth", "Preview · copying disabled") : service.busy ? I18n.trFor("enteAuth", "Please wait…") : service.unlocked ? (service.state.syncStatus === "current" ? I18n.trFor("enteAuth", "Up to date") : service.state.syncStatus === "error" ? I18n.trFor("enteAuth", "Sync error") : I18n.trFor("enteAuth", "Offline · cached codes")) + " · " + (service.state.syncedAt ? Qt.formatTime(new Date(service.state.syncedAt), "HH:mm") : "—") : I18n.trFor("enteAuth", "Locked")
                font.pixelSize: Theme.fontSizeSmall; color: Theme.surfaceVariantText; elide: Text.ElideRight
            }
            DankButton {
                visible: !!service.state.hasAccount && !service.demo
                buttonHeight: Math.round(Theme.fontSizeSmall * 2.8)
                backgroundColor: logoutConfirm ? Theme.error : Theme.surfaceContainerHigh
                textColor: logoutConfirm ? Theme.surface : Theme.surfaceText
                text: logoutConfirm ? I18n.trFor("enteAuth", "Confirm sign out") : I18n.trFor("enteAuth", "Sign out")
                enabled: !service.busy
                onClicked: { if (logoutConfirm) { service.operate("logout", {}); logoutConfirm = false; } else logoutConfirm = true; }
            }
        }
    }
}
