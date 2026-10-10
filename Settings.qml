import QtQuick
import qs.Common
import qs.Widgets
import qs.Modules.Plugins

PluginSettings {
    pluginId: "enteAuth"
    StringSetting { settingKey: "serverUrl"; label: I18n.trFor("enteAuth", "Ente server"); description: I18n.trFor("enteAuth", "Leave empty for Ente Cloud. Applies when signing in to a new account."); placeholder: "https://api.ente.io/" }
    StringSetting { settingKey: "accountsUrl"; label: I18n.trFor("enteAuth", "Ente Accounts URL"); placeholder: "https://accounts.ente.io/" }
    SliderSetting { settingKey: "lockMinutes"; label: I18n.trFor("enteAuth", "Lock after inactivity"); defaultValue: 5; minimum: 1; maximum: 60; unit: "min" }
    SliderSetting { settingKey: "syncMinutes"; label: I18n.trFor("enteAuth", "Sync interval"); defaultValue: 5; minimum: 1; maximum: 60; unit: "min" }
    ToggleSetting { settingKey: "closeAfterCopy"; label: I18n.trFor("enteAuth", "Close popout after copying"); defaultValue: false }
    ToggleSetting { settingKey: "demoMode"; label: I18n.trFor("enteAuth", "Demo mode"); description: I18n.trFor("enteAuth", "Show sample entries without connecting to Ente. Copying is disabled."); defaultValue: false }
}
