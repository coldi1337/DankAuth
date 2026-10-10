import {build} from 'esbuild';
import {readFile, mkdir, readdir, copyFile, rm, writeFile} from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
await build({absWorkingDir: root, entryPoints: ['backend/main.ts'], bundle: true, platform: 'node', format: 'esm', target: 'node20', outfile: 'backend/dist/main.js',
    banner: {js: "import {createRequire as createNodeRequire} from 'node:module'; import {fileURLToPath as bundleFileURLToPath} from 'node:url'; import {dirname as bundleDirname} from 'node:path'; const require = createNodeRequire(import.meta.url); const __filename = bundleFileURLToPath(import.meta.url); const __dirname = bundleDirname(__filename);"}, logLevel: 'info'});
// Ship dependency notices with the bundled release, including transitive packages.
const licenses = path.join(root, 'backend/licenses');
await rm(licenses, {recursive: true, force: true}); await mkdir(licenses, {recursive: true});
const seen = new Set(), notices = [];
async function collect(name) {
    if (seen.has(name)) return; seen.add(name);
    const dir = path.join(root, 'node_modules', name), pkg = JSON.parse(await readFile(path.join(dir, 'package.json'), 'utf8'));
    const files = (await readdir(dir)).filter(file => /^(license|licence|copying)(\.|$)/i.test(file));
    if (!files.length) throw new Error('Missing license for ' + name);
    const dest = path.join(licenses, name.replaceAll('/', '__')); await mkdir(dest, {recursive: true});
    for (const file of files) await copyFile(path.join(dir, file), path.join(dest, file));
    notices.push(`${name} ${pkg.version} — ${pkg.license || 'see license file'}`);
    for (const dependency of Object.keys(pkg.dependencies || {})) await collect(dependency);
}
const pkg = JSON.parse(await readFile(path.join(root, 'package.json'), 'utf8'));
for (const name of Object.keys(pkg.dependencies)) await collect(name);
await writeFile(path.join(licenses, 'NOTICE.txt'), notices.sort().join('\n') + '\n');
