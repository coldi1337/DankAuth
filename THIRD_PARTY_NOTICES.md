# Herkunft der Komponenten

`backend/vendor/` übernimmt folgende Dateien aus `aheimowitz/ente-auth-extension`, Commit `78e7ff8668c60b2fc31268293698de0e7014349c`, unter AGPL-3.0:

`api.ts`, `api-auth.ts`, `code.ts`, `crypto.ts`, `otp.ts`, `srp.ts`, `steam.ts`, `types.ts`, `libsodium.d.ts`.

Quelle: https://github.com/aheimowitz/ente-auth-extension. Das Projekt enthält seinerseits aus dem Ente-Code adaptierte Helfer. Die Kommentare zur Herkunft bleiben in den Dateien erhalten. Der vollständige Lizenztext des Ausgangsprojekts steht in `LICENSE`.

Lokale Anpassungen am übernommenen Code:

- `code.ts`: Groß-/Kleinschreibung im Konto-Pfad bleibt erhalten.
- `api.ts`: Zeitkorrektur für OTPs als Serverzeit minus lokale Zeit; Abbruch einer nicht fortschreitenden Diff-Paginierung.

Weitere Laufzeitabhängigkeiten: `fast-srp-hap`, `libsodium-wrappers-sumo`/`libsodium-sumo`, `otpauth`, `jssha` und `zod`. Für den Build wird `esbuild` verwendet. Genaue Versionen stehen in `package-lock.json`; die Laufzeitpakete werden vollständig in backend/dist/main.js gebündelt. Ihre Lizenzdateien und eine Paketübersicht liegen unter backend/licenses/. npm wird nur für Entwicklung und Build benötigt.

DankChat und Bitwarden Dankbar dienen als lokale Referenz für Struktur, Bar-Positionierung und DMS-Komponenten. Es werden keine kompletten Module oder Backends dieser Plugins mitgeliefert. DMS-Komponenten und Theme-Werte werden aus der DMS-Installation importiert.

`AuthLogo.qml` ist eine eigene vereinfachte Zeichnung, inspiriert von der Kombination aus rundem e und kleinem Schild im sichtbaren Markenzeichen auf https://ente.com/auth/ (angesehen am 10. Oktober 2026). Es werden weder SVG-Pfade noch Bilddateien des Original-Logos mitgeliefert. Ente und Ente Auth sind Marken ihrer jeweiligen Rechteinhaber.
