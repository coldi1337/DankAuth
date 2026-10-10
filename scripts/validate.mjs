import {readFile, readdir, access} from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import assert from 'node:assert/strict';
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const manifest = JSON.parse(await readFile(path.join(root, 'plugin.json'), 'utf8'));
assert.match(manifest.id, /^[a-z][A-Za-z0-9]*$/);
assert.match(manifest.version, /^\d+\.\d+\.\d+$/);
assert.equal(manifest.name, 'DankAuth');
assert.equal(manifest.type, 'composite');
assert.ok(manifest.permissions.includes('settings_write'));
for (const file of [...Object.values(manifest.components), manifest.settings, manifest.startupCheck]) {
    assert.match(file, /^\.\/.+\.qml$/); await access(path.join(root, file));
}
const german = JSON.parse(await readFile(path.join(root, 'translations/de.json'), 'utf8'));
const terms = new Set();
for (const name of (await readdir(root)).filter(name => name.endsWith('.qml'))) {
    const source = await readFile(path.join(root, name), 'utf8');
    assert.ok(!/\b(?:root\.)?tr\(/.test(source), `${name}: use literal I18n.trFor calls`);
    for (const match of source.matchAll(/I18n\.trFor\("enteAuth",\s*("(?:[^"\\]|\\.)*")\)/g)) terms.add(JSON.parse(match[1]));
    assert.ok(!/#[a-fA-F0-9]{6}\b/.test(source), `${name}: hard-coded theme color`);
}
for (const term of terms) assert.ok(typeof german[term]?.[term] === 'string' && german[term][term].length, `Missing German: ${term}`);
assert.ok(!manifest.dependencies.includes('wl-clipboard'));
await access(path.join(root, 'backend/dist/main.js')); await access(path.join(root, 'backend/licenses/NOTICE.txt'));
const registry = JSON.parse(await readFile(path.join(root, 'registry/coldi1337-dankauth.json'), 'utf8'));
for (const key of ['id', 'name', 'author', 'description']) assert.equal(registry[key], manifest[key], `Registry ${key} differs`);
assert.ok(!registry.i18n, 'Central POEditor approval must happen separately');
console.log(`PASS: manifest, component paths, bundled runtime, registry metadata and ${terms.size} literal English terms with German translations`);
