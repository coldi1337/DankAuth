import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp, readFile, stat, rm, symlink, writeFile} from 'node:fs/promises';
import {spawn} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import {randomBytes} from 'node:crypto';
import {SRP, SrpServer} from 'fast-srp-hap';
import {tmpdir} from 'node:os';
import path from 'node:path';
import sodium from 'libsodium-wrappers-sumo';
import {Vault, displayCodes, endpoint, clipboardOffers} from '../backend/dist/main.js';

const b64 = value => sodium.to_base64(value, sodium.base64_variants.ORIGINAL);
const secret = 'GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ';
const fixture = {id: 'test', issuer: 'Example', account: 'MixedCase@Example.org', type: 'totp', length: 8,
    period: 30, algorithm: 'sha1', secret, uriString: 'otpauth://totp/Example?secret=' + secret,
    codeDisplay: {tags: ['Test'], pinned: true}};
async function setup(t) {
    await sodium.ready;
    const dir = await mkdtemp(path.join(tmpdir(), 'ente-test-'));
    t.after(() => rm(dir, {recursive: true, force: true}));
    const vault = new Vault(path.join(dir, 'private/vault.json'));
    t.after(() => vault.lock());
    const salt = b64(sodium.randombytes_buf(sodium.crypto_pwhash_SALTBYTES));
    const kekBytes = sodium.crypto_pwhash(32, 'test-password', sodium.from_base64(salt, sodium.base64_variants.ORIGINAL), 1, 8192, sodium.crypto_pwhash_ALG_ARGON2ID13);
    const kek = b64(kekBytes), master = sodium.crypto_secretbox_keygen();
    const nonce = sodium.randombytes_buf(24);
    const attrs = {kekSalt: salt, opsLimit: 1, memLimit: 8192,
        encryptedKey: b64(sodium.crypto_secretbox_easy(master, nonce, kekBytes)), keyDecryptionNonce: b64(nonce)};
    vault.email = 'test@example.org';
    vault.remote = async () => ({codes: [fixture], timeOffset: 0});
    await vault.finish({token: 'test-token', keyAttributes: attrs}, kek, vault.epoch);
    return vault;
}

test('RFC 6238 OTP and sanitized display data', () => {
    const rows = displayCodes([fixture], 59000 - Date.now());
    assert.equal(rows[0].otp, '94287082');
    assert.equal(rows[0].remaining, 1);
    assert.equal(rows[0].account, fixture.account);
    assert.ok(!JSON.stringify(rows).includes(secret));
    assert.ok(!('uriString' in rows[0]));
});
test('encrypted storage, offline unlock and logout', async t => {
    const vault = await setup(t);
    const text = await readFile(vault.file, 'utf8');
    for (const plaintext of [secret, 'test-token', fixture.uriString, fixture.account]) assert.ok(!text.includes(plaintext));
    assert.equal((await stat(vault.file)).mode & 0o777, 0o600);
    vault.lock(); assert.throws(() => vault.list(), /Locked/);
    await assert.rejects(vault.password('wrong-password'));
    assert.equal(vault.masterKey, '');
    await vault.password('test-password');
    assert.equal(vault.list().length, 1);
    const restarted = new Vault(vault.file); t.after(() => restarted.lock());
    assert.equal((await restarted.init()).step, 'locked');
    await restarted.password('test-password'); assert.equal(restarted.list().length, 1);
    await restarted.logout(); await assert.rejects(readFile(vault.file));
});
test('locking cancels a late sync without restoring secrets', async t => {
    const vault = await setup(t);
    let resolve;
    vault.remote = () => new Promise(r => { resolve = r; });
    const syncing = vault.sync(); vault.lock();
    resolve({codes: [fixture], timeOffset: 0});
    await assert.rejects(syncing, /cancelled/);
    assert.equal(vault.codes.length, 0); assert.equal(vault.token, ''); assert.equal(vault.masterKey, '');
});
test('failed sync preserves the last usable snapshot', async t => {
    const vault = await setup(t);
    vault.remote = async () => { throw new Error('offline'); };
    await assert.rejects(vault.sync()); assert.equal(vault.list().length, 1);
});
test('background activity cannot extend the inactivity timer', async t => {
    const vault = await setup(t);
    vault.timeout = 20;
    let locked;
    const result = new Promise(resolve => { locked = resolve; });
    vault.onLock = locked; vault.touch();
    vault.list(); await vault.sync(); await result;
    assert.equal(vault.masterKey, '');
});
test('HOTP is displayed without a reusable code or incrementing counters', () => {
    const row = displayCodes([{...fixture, type: 'hotp', counter: 9}], 0)[0];
    assert.equal(row.otp, ''); assert.equal(row.remaining, 0); assert.ok(!('counter' in row));
});
test('reject remote HTTP and credentials in endpoints', () => {
    assert.equal(endpoint('http://localhost:8080'), 'http://localhost:8080/');
    for (const url of ['http://example.org', 'https://user:pass@example.org', 'file:///tmp/vault', 'https://example.org/?token=secret']) assert.throws(() => endpoint(url));
});
test('SRP login completes with a checked server proof', async t => {
    const vault = await setup(t), saved = vault.stored;
    vault.lock(); vault.stored = null;
    const attrs = saved.keyAttributes;
    const kek = sodium.crypto_pwhash(32, 'test-password', sodium.from_base64(attrs.kekSalt, sodium.base64_variants.ORIGINAL), attrs.opsLimit, attrs.memLimit, sodium.crypto_pwhash_ALG_ARGON2ID13);
    const loginKey = sodium.crypto_kdf_derive_from_key(32, 1, 'loginctx', kek).slice(0, 16);
    const salt = randomBytes(16), userID = 'synthetic-user';
    const server = new SrpServer(SRP.params['4096'], SRP.computeVerifier(SRP.params['4096'], salt, Buffer.from(userID), Buffer.from(loginKey)), randomBytes(32));
    const originalFetch = globalThis.fetch; t.after(() => { globalThis.fetch = originalFetch; });
    globalThis.fetch = async (url, init) => {
        const route = new URL(url).pathname;
        if (route === '/users/srp/attributes') return Response.json({attributes: {...attrs, srpUserID: userID, srpSalt: salt.toString('base64'), isEmailMFAEnabled: false}});
        if (route === '/users/srp/create-session') {
            server.setA(Buffer.from(JSON.parse(init.body).srpA, 'base64'));
            return Response.json({sessionID: 'synthetic-session', srpB: server.computeB().toString('base64')});
        }
        if (route === '/users/srp/verify-session') {
            server.checkM1(Buffer.from(JSON.parse(init.body).srpM1, 'base64'));
            return Response.json({srpM2: server.computeM2().toString('base64'), token: 'test-token', keyAttributes: attrs});
        }
        throw new Error('Unexpected request');
    };
    assert.equal((await vault.loginStart('test@example.org', '')).step, 'password');
    assert.equal((await vault.password('test-password')).step, 'unlocked');
    assert.equal(vault.list().length, 1);
});
test('email login, second factor and local password decryption', async t => {
    const vault = await setup(t), saved = vault.stored;
    vault.lock(); vault.stored = null;
    const originalFetch = globalThis.fetch; t.after(() => { globalThis.fetch = originalFetch; });
    globalThis.fetch = async (url, init) => {
        const route = new URL(url).pathname;
        if (route === '/users/srp/attributes') return new Response('', {status: 404});
        if (route === '/users/ott') return new Response('', {status: 200});
        if (route === '/users/verify-email') {
            assert.equal(JSON.parse(init.body).ott, 'email-code');
            return Response.json({twoFactorSessionIDV2: 'synthetic-session'});
        }
        if (route === '/users/two-factor/verify') {
            assert.equal(JSON.parse(init.body).sessionID, 'synthetic-session');
            return Response.json({keyAttributes: saved.keyAttributes, token: 'test-token'});
        }
        throw new Error('Unexpected request');
    };
    assert.equal((await vault.loginStart('test@example.org', '')).step, 'email-code');
    assert.equal((await vault.verify('email-code')).step, 'two-factor');
    assert.equal((await vault.verify('123456')).step, 'password-decrypt');
    assert.equal((await vault.password('test-password')).step, 'unlocked');
});
test('passkey URL and polling preserve pending login context', async t => {
    const vault = await setup(t), attrs = vault.stored.keyAttributes;
    vault.lock(); vault.stored = null;
    await vault.route({passkeySessionID: 'synthetic-passkey'}, undefined, vault.epoch);
    assert.equal(vault.step, 'passkey');
    const url = new URL(vault.passkeyURL());
    assert.equal(url.origin, 'https://accounts.ente.io');
    assert.equal(url.searchParams.get('passkeySessionID'), 'synthetic-passkey');
    const originalFetch = globalThis.fetch; t.after(() => { globalThis.fetch = originalFetch; });
    globalThis.fetch = async () => new Response('', {status: 400});
    assert.equal((await vault.pollPasskey()).step, 'passkey');
    globalThis.fetch = async () => Response.json({keyAttributes: attrs, token: 'test-token'});
    assert.equal((await vault.pollPasskey()).step, 'password-decrypt');
});
test('stdio bridge starts through the installed symlink and stops cleanly', async t => {
    const dir = await mkdtemp(path.join(tmpdir(), 'ente-link-test-'));
    t.after(() => rm(dir, {recursive: true, force: true}));
    const link = path.join(dir, 'plugin');
    await symlink(fileURLToPath(new URL('..', import.meta.url)), link);
    const child = spawn(process.execPath, [path.join(link, 'backend/dist/main.js')], {env: {...process.env, XDG_STATE_HOME: path.join(dir, 'state')}, stdio: ['pipe', 'pipe', 'pipe']});
    t.after(() => child.kill());
    let output = '';
    await new Promise((resolve, reject) => {
        const timeout = setTimeout(() => reject(new Error('Bridge did not start')), 3000);
        child.on('error', reject);
        child.stdout.on('data', chunk => {
            output += chunk;
            if (output.includes('"event":"ready"')) { clearTimeout(timeout); resolve(); }
        });
    });
    assert.equal(JSON.parse(output.trim()).state.step, 'email');
    child.stdin.end();
    const code = await new Promise(resolve => child.on('exit', resolve)); assert.equal(code, 0);
});

test('OTP updates contain only selected IDs and short-lived code data', async t => {
    const vault = await setup(t);
    const update = vault.updates(['test'])[0];
    assert.deepEqual(Object.keys(update).sort(), ['expiresAt', 'id', 'invalid', 'otp']);
    assert.ok(update.expiresAt > Date.now() && update.expiresAt <= Date.now() + 30000);
    assert.deepEqual(vault.updates(['missing']), []);
    assert.equal(vault.state().syncStatus, 'current');
    vault.lock(); await vault.password('test-password');
    assert.equal(vault.state().syncStatus, 'cached');
    vault.remote = async () => { throw new Error('offline'); };
    await assert.rejects(vault.sync());
    assert.equal(vault.state().syncStatus, 'offline');
    assert.equal(vault.updates().length, 1);
});

test('metadata writes are encrypted and preserve remote URI, note and unknown fields', async t => {
    const vault = await setup(t);
    const key = sodium.crypto_secretbox_keygen(), nonce = sodium.randombytes_buf(24);
    vault.entityKey = async () => ({encryptedKey: b64(sodium.crypto_secretbox_easy(key, nonce, sodium.from_base64(vault.masterKey, sodium.base64_variants.ORIGINAL))), header: b64(nonce)});
    const latest = {...fixture, codeDisplay: {pinned: true, tags: ['Remote'], note: 'Preserve me'},
        uriString: fixture.uriString + '&custom=keep&codeDisplay=' + encodeURIComponent(JSON.stringify({pinned: true, tags: ['Remote'], note: 'Preserve me', future: 'keep'}))};
    vault.remote = async () => ({codes: [latest], timeOffset: 0});
    let writes = 0;
    vault.updateEntity = async (_token, request) => {
        writes++;
        assert.equal(request.id, 'test');
        assert.ok(!JSON.stringify(request).includes(secret));
        const state = sodium.crypto_secretstream_xchacha20poly1305_init_pull(sodium.from_base64(request.header, sodium.base64_variants.ORIGINAL), key);
        const decrypted = sodium.crypto_secretstream_xchacha20poly1305_pull(state, sodium.from_base64(request.encryptedData, sodium.base64_variants.ORIGINAL));
        const uri = new URL(JSON.parse(sodium.to_string(decrypted.message)));
        assert.equal(uri.searchParams.get('custom'), 'keep');
        assert.equal(uri.searchParams.get('secret'), secret);
        const display = JSON.parse(uri.searchParams.get('codeDisplay'));
        assert.equal(display.note, 'Preserve me'); assert.equal(display.future, 'keep');
        if (writes === 1) { assert.equal(display.pinned, false); assert.deepEqual(display.tags, ['Remote']); }
        else { assert.equal(display.pinned, true); assert.deepEqual(display.tags, ['One', 'Two']); }
    };
    await vault.metadata({id: 'test', pinned: false});
    await vault.metadata({id: 'test', tags: [' One ', 'Two', 'One', '']});
    assert.equal(writes, 2);
    vault.updateEntity = async () => { throw new Error('write failed'); };
    await assert.rejects(vault.metadata({id: 'test', pinned: false}));
    assert.equal(vault.codes[0].codeDisplay.pinned, true);
    await assert.rejects(vault.metadata({id: 'test', tags: [123]}));
    await assert.rejects(vault.metadata({id: 'removed', pinned: true}));
});

test('lock during metadata read prevents a remote write', async t => {
    const vault = await setup(t);
    let resolve, writes = 0;
    vault.remote = () => new Promise(done => { resolve = done; });
    vault.updateEntity = async () => { writes++; };
    const operation = vault.metadata({id: 'test', pinned: false});
    vault.lock(); resolve({codes: [fixture], timeOffset: 0});
    await assert.rejects(operation, /cancelled/);
    assert.equal(writes, 0); assert.equal(vault.codes.length, 0);
});


test('native clipboard framing preserves text MIME offers and sensitive hint', () => {
    const data = Buffer.from('ä123456');
    const frame = clipboardOffers(data);
    const offers = {};
    let offset = 0;
    while (offset < frame.length) {
        const mimeEnd = frame.indexOf(0, offset);
        const mime = frame.subarray(offset, mimeEnd).toString();
        const sizeEnd = frame.indexOf(0, mimeEnd + 1);
        const size = Number(frame.subarray(mimeEnd + 1, sizeEnd).toString());
        offset = sizeEnd + 1;
        offers[mime] = frame.subarray(offset, offset + size).toString();
        offset += size;
    }
    assert.deepEqual(offers, {'text/plain;charset=utf-8': 'ä123456', 'text/plain': 'ä123456', UTF8_STRING: 'ä123456', 'x-kde-passwordManagerHint': 'secret'});
});

test('native clipboard acknowledges ownership, avoids OTP arguments and releases on lock', async t => {
    const vault = await setup(t);
    const dir = path.dirname(vault.file);
    const record = path.join(dir, 'offers');
    const executable = path.join(dir, 'dms');
    await writeFile(executable, `#!${process.execPath}
const fs = require('node:fs');
let data = [];
process.stdin.on('data', chunk => data.push(chunk));
process.stdin.on('end', () => {
    fs.writeFileSync(${JSON.stringify(record)}, JSON.stringify({args: process.argv.slice(2), data: Buffer.concat(data).toString('base64')}));
    process.stdout.write(Buffer.from([1]));
    setInterval(() => {}, 1000);
});
`, {mode: 0o700});
    const previousPath = process.env.PATH;
    process.env.PATH = dir + path.delimiter + previousPath;
    t.after(() => { process.env.PATH = previousPath; });
    await vault.copy('test');
    const child = vault.clipboard;
    const saved = JSON.parse(await readFile(record, 'utf8'));
    assert.deepEqual(saved.args, ['cl', 'copy', '--foreground', '--type', '__multi__']);
    assert.ok(Buffer.from(saved.data, 'base64').includes(Buffer.from('x-kde-passwordManagerHint')));
    const exited = new Promise(resolve => child.once('exit', resolve));
    vault.lock(); await exited;
    assert.equal(vault.clipboard, null);
    await writeFile(executable, `#!${process.execPath}
process.exit(7);
`, {mode: 0o700});
    await vault.password('test-password');
    await assert.rejects(vault.copy('test'), /Clipboard unavailable/);
});
