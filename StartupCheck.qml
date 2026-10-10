import QtQuick
import qs.Common

QtObject {
    id: root
    function check(done) {
        Proc.runCommand("enteAuth.dependencies", ["sh", Qt.resolvedUrl("scripts/check-dependencies").toString().replace("file://", "")], (stdout, exitCode) => {
            if (exitCode === 0) { done(null); return; }
            const reason = stdout.trim();
            done({
                title: I18n.trFor("enteAuth", "DankAuth could not start"),
                details: reason === "NODE_MISSING" || reason === "NODE_OLD"
                    ? I18n.trFor("enteAuth", "Install Node.js 20 or newer, then enable DankAuth again.")
                    : reason === "DMS_MISSING"
                        ? I18n.trFor("enteAuth", "DankAuth requires DankMaterialShell 1.6.2 or newer on your PATH.")
                        : I18n.trFor("enteAuth", "The bundled service is missing or damaged. Reinstall DankAuth or run scripts/setup, then enable it again.")
            });
        }, 0, 10000, root);
    }
}
