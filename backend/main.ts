import { promises as fs, realpathSync } from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import readline from 'node:readline';
import { fileURLToPath } from 'node:url';
import { spawn, execFile } from 'node:child_process';
import { APIError, getAuthCodes, setApiBaseUrl, getAuthenticatorEntityKey, updateAuthenticatorEntity } from './vendor/api';
import * as authAPI from './vendor/api-auth';
import { verifySRP } from './vendor/srp';
import { deriveKey, decryptBox, encryptMetadataJSON, decryptBoxBytes, encryptBox, boxSealOpenBytes, toB64, toB64URLSafe } from './vendor/crypto';
import { generateOTPs, getRemainingSeconds } from './vendor/otp';
import type { Code, KeyAttributes } from './vendor/types';

const bytes = (s: string) => new TextEncoder().encode(s);
const decode = (b: Uint8Array) => new TextDecoder().decode(b);
export function endpoint(value = '') {
    const url = new URL(value || 'https://api.ente.io/');
    if (url.username || url.password || url.search || url.hash ||
        (url.protocol !== 'https:' && !(url.protocol === 'http:' && ['localhost', '127.0.0.1', '[::1]'].includes(url.hostname))))
        throw new Error('Invalid endpoint');
    return url.toString().replace(/\/*$/, '/');
}

// Only display data and short-lived OTPs cross the pipe. Secrets and URIs stay here.
export function displayCodes(codes: Code[], offset: number) {
    return codes.map(c => {
        let otp = '', invalid = false;
        try { if (c.type !== 'hotp') otp = generateOTPs(c, offset)[0]; } catch { invalid = true; }
        return {id: c.id, issuer: c.issuer, account: c.account || '', type: c.type,
            tags: c.codeDisplay?.tags || [], pinned: !!c.codeDisplay?.pinned,
            expiresAt: c.type === 'hotp' ? 0 : (Math.floor((Date.now() + offset) / (c.period * 1000)) + 1) * c.period * 1000 - offset,
            period: c.period, remaining: c.type === 'hotp' ? 0 : getRemainingSeconds(c, offset), otp, invalid};
    });
}

export function clipboardOffers(data: Buffer, sensitive = true) {
    const offers: [string, Buffer][] = [
        ['text/plain;charset=utf-8', data], ['text/plain', data], ['UTF8_STRING', data]
    ];
    if (sensitive) offers.push(['x-kde-passwordManagerHint', Buffer.from('secret')]);
    return Buffer.concat(offers.flatMap(([mime, value]) => [Buffer.from(`${mime}\0${value.length}\0`), value]));
}

export class Vault {
    file: string;
    stored: any = null;
    codes: Code[] = [];
    token = '';
    masterKey = '';
    pending: any = null;
    step = 'email';
    email = '';
    server = endpoint();
    accounts = 'https://accounts.ente.io/';
    epoch = 0;
    offset = 0;
    syncedAt = 0;
    syncStatus = 'cached';
    timeout = 300000;
    timer: any = null;
    clipboard: any = null;
    clipboardTimer: any = null;
    onLock = () => {};
    remote = getAuthCodes;
    entityKey = getAuthenticatorEntityKey;
    updateEntity = updateAuthenticatorEntity;
    constructor(file: string) { this.file = file; }
    async init() {
        try {
            this.stored = JSON.parse(await fs.readFile(this.file, 'utf8'));
            if (this.stored.version !== 1 || !this.stored.keyAttributes || !this.stored.credentials) throw new Error();
            this.server = endpoint(this.stored.server); this.email = this.stored.email; this.step = 'locked';
        } catch (e: any) { if (e.code !== 'ENOENT') throw new Error('Saved vault cannot be read'); }
        return this.state();
    }
    check(epoch: number) { if (epoch !== this.epoch) throw new Error('Operation cancelled'); }
    state() {
        return {step: this.step, unlocked: !!this.masterKey, email: this.email, server: this.server,
            syncStatus: this.syncStatus, hasAccount: !!this.stored, syncedAt: this.syncedAt, count: this.codes.length,
            passkey: !!this.pending?.passkeySessionID, twoFactor: !!(this.pending?.twoFactorSessionID || this.pending?.twoFactorSessionIDV2)};
    }
    touch() {
        clearTimeout(this.timer); this.timer = null;
        if (this.masterKey || this.pending) this.timer = setTimeout(() => { this.lock(); this.onLock(); }, this.timeout);
    }
    lock() {
        this.epoch++; this.masterKey = ''; this.token = ''; this.codes = []; this.pending = null;
        this.offset = 0; this.syncedAt = 0; clearTimeout(this.timer); this.timer = null;
        this.clipboard?.kill(); this.clipboard = null; clearTimeout(this.clipboardTimer);
        this.step = this.stored ? 'locked' : 'email';
        if (this.stored) { this.email = this.stored.email; this.server = endpoint(this.stored.server); }
        return this.state();
    }
    async logout() { this.lock(); await fs.rm(this.file, {force: true}); this.stored = null; this.email = ''; this.step = 'email'; return this.state(); }
    configure(params: any) {
        this.timeout = Math.min(60, Math.max(1, Number(params.lockMinutes) || 5)) * 60000;
        this.accounts = endpoint(params.accountsUrl || 'https://accounts.ente.io/');
        this.touch(); return this.state();
    }
    async save(epoch: number) {
        this.check(epoch);
        await fs.mkdir(path.dirname(this.file), {recursive: true, mode: 0o700});
        const temporary = this.file + '.tmp';
        await fs.writeFile(temporary, JSON.stringify(this.stored), {mode: 0o600});
        this.check(epoch); await fs.rename(temporary, this.file); await fs.chmod(this.file, 0o600);
    }
    async master(attrs: KeyAttributes, kek: string) {
        return toB64(await decryptBoxBytes({encryptedData: attrs.encryptedKey, nonce: attrs.keyDecryptionNonce}, kek));
    }
    async finish(response: any, kek: string, epoch: number) {
        const attrs = response.keyAttributes;
        if (!attrs) throw new Error('Missing key attributes');
        const masterKey = await this.master(attrs, kek);
        let token = response.token;
        if (!token && response.encryptedToken) {
            const privateKey = await toB64(await decryptBoxBytes({encryptedData: attrs.encryptedSecretKey, nonce: attrs.secretKeyDecryptionNonce}, masterKey));
            token = await toB64URLSafe(await boxSealOpenBytes(response.encryptedToken, {publicKey: attrs.publicKey, privateKey}));
        }
        if (!token) throw new Error('Missing token');
        const credentials = await encryptBox(await toB64(bytes(token)), kek);
        this.check(epoch);
        this.stored = {version: 1, email: this.email, server: this.server, keyAttributes: attrs, credentials};
        await this.save(epoch); this.check(epoch);
        this.masterKey = masterKey; this.token = token; this.pending = null; this.step = 'unlocked'; this.touch();
        // A failed first sync still leaves a usable authenticated session for retry.
        try { await this.sync(epoch); } catch { this.check(epoch); return {...this.state(), warning: 'sync_failed'}; }
        return this.state();
    }
    async route(response: any, kek: string | undefined, epoch: number) {
        this.check(epoch);
        this.pending = {...response, kek}; this.touch();
        if (response.twoFactorSessionID || response.twoFactorSessionIDV2) this.step = 'two-factor';
        else if (response.passkeySessionID) this.step = 'passkey';
        else if (!kek) this.step = 'password-decrypt';
        else return this.finish(response, kek, epoch);
        return this.state();
    }
    async loginStart(email: string, server: string) {
        this.lock(); const epoch = this.epoch;
        const nextServer = endpoint(server);
        if (!email || !email.includes('@')) throw new Error('Invalid email');
        const nextEmail = email.trim();
        const attrs = await authAPI.getSRPAttributes(nextServer, nextEmail); this.check(epoch);
        this.email = nextEmail; this.server = nextServer;
        this.pending = {attrs}; this.touch();
        if (attrs && !attrs.isEmailMFAEnabled) this.step = 'password';
        else { await authAPI.requestEmailOTT(this.server, this.email); this.check(epoch); this.step = 'email-code'; }
        return this.state();
    }
    async password(password: string) {
        const epoch = this.epoch;
        if (this.step === 'locked' && this.stored) {
            const saved = this.stored, attrs = saved.keyAttributes;
            const kek = await deriveKey(password, attrs.kekSalt, attrs.opsLimit, attrs.memLimit);
            const masterKey = await this.master(attrs, kek);
            const token = decode(await decryptBoxBytes(saved.credentials, kek));
            let cached: any = {codes: [], offset: 0, syncedAt: 0};
            if (saved.cache) cached = JSON.parse(decode(await decryptBoxBytes(saved.cache, masterKey)));
            this.check(epoch);
            this.masterKey = masterKey; this.token = token; this.codes = cached.codes; this.offset = cached.offset;
            this.email = saved.email; this.server = endpoint(saved.server);
            this.syncStatus = 'cached'; this.syncedAt = cached.syncedAt; this.step = 'unlocked'; this.touch();
            return this.state();
        }
        if (!['password', 'password-decrypt'].includes(this.step) || !this.pending) throw new Error('Unexpected password');
        const pending = this.pending;
        const attrs = this.step === 'password' ? pending.attrs : pending.keyAttributes;
        if (!attrs) throw new Error('Missing attributes');
        const kek = await deriveKey(password, attrs.kekSalt, attrs.opsLimit, attrs.memLimit); this.check(epoch);
        if (this.step === 'password') return this.route(await verifySRP(this.server, attrs, kek), kek, epoch);
        return this.finish(pending, kek, epoch);
    }
    async verify(code: string) {
        const epoch = this.epoch, pending = this.pending;
        let response: any;
        if (this.step === 'email-code') response = await authAPI.verifyEmail(this.server, this.email, code.trim());
        else if (this.step === 'two-factor' && pending) response = await authAPI.verifyTwoFactor(this.server, pending.twoFactorSessionID || pending.twoFactorSessionIDV2, code.trim());
        else throw new Error('Unexpected verification');
        return this.route(response, pending?.kek, epoch);
    }
    passkeyURL() {
        if (!this.pending?.passkeySessionID) throw new Error('No passkey session');
        const url = new URL('passkeys/verify', this.accounts);
        url.search = new URLSearchParams({passkeySessionID: this.pending.passkeySessionID, clientPackage: 'io.ente.auth.web', redirect: this.accounts.replace(/\/$/, '')}).toString();
        return url.toString();
    }
    async pollPasskey() {
        const epoch = this.epoch, pending = this.pending;
        if (!pending?.passkeySessionID) throw new Error('No passkey session');
        const response = await authAPI.checkPasskeyVerificationStatus(this.server, pending.passkeySessionID); this.check(epoch);
        return response ? this.route(response, pending.kek, epoch) : this.state();
    }
    async sync(epoch = this.epoch) {
        if (!this.masterKey) throw new Error('Locked');
        setApiBaseUrl(this.server);
        let result;
        try { result = await this.remote(this.token, this.masterKey); } catch (error) { this.check(epoch); this.syncStatus = error instanceof APIError && error.status < 500 ? 'error' : this.codes.length ? 'offline' : 'error'; throw error; }
        this.check(epoch);
        const codes = result.codes, offset = result.timeOffset ?? this.offset, syncedAt = Date.now();
        const cache = await encryptBox(await toB64(bytes(JSON.stringify({codes, offset, syncedAt}))), this.masterKey); this.check(epoch);
        this.stored = {...this.stored, cache}; await this.save(epoch); this.check(epoch);
        this.codes = codes; this.offset = offset; this.syncedAt = syncedAt; this.syncStatus = 'current';
        return this.state();
    }
    updates(ids?: string[]) {
        if (!this.masterKey) throw new Error('Locked');
        return displayCodes(ids ? this.codes.filter(code => ids.includes(code.id)) : this.codes, this.offset).map(({id, otp, expiresAt, invalid}) => ({id, otp, expiresAt, invalid}));
    }
    async metadata(params: any) {
        if (!this.masterKey) throw new Error('Locked');
        const epoch = this.epoch, token = this.token, master = this.masterKey;
        if (typeof params.id !== 'string' || (params.pinned !== undefined && typeof params.pinned !== 'boolean') ||
            (params.tags !== undefined && (!Array.isArray(params.tags) || params.tags.length > 50 || params.tags.some((tag: any) => typeof tag !== 'string' || tag.length > 100)))) throw new Error('Invalid metadata');
        setApiBaseUrl(this.server);
        // Read the latest remote URI to preserve other devices' metadata and unknown parameters.
        const latest = await this.remote(token, master); this.check(epoch);
        const code = latest.codes.find(c => c.id === params.id);
        if (!code) throw new Error('Entry removed');
        const uri = new URL(code.uriString);
        const display = {...JSON.parse(uri.searchParams.get('codeDisplay') || '{}')};
        if (params.pinned !== undefined) display.pinned = params.pinned;
        if (params.tags !== undefined) display.tags = [...new Set<string>(params.tags.map((tag: string) => tag.trim()).filter(Boolean))];
        uri.searchParams.set('codeDisplay', JSON.stringify(display));
        const key = await this.entityKey(token); this.check(epoch);
        if (!key) throw new Error('Missing entity key');
        const entityKey = await decryptBox({encryptedData: key.encryptedKey, nonce: key.header}, master); this.check(epoch);
        const encrypted = await encryptMetadataJSON(uri.toString(), entityKey); this.check(epoch);
        await this.updateEntity(token, {id: code.id, encryptedData: encrypted.encryptedData, header: encrypted.decryptionHeader}); this.check(epoch);
        this.touch();
        return this.sync(epoch);
    }
    list() { if (!this.masterKey) throw new Error('Locked'); return displayCodes(this.codes, this.offset); }
    async copy(id: string) {
        if (!this.masterKey) throw new Error('Locked');
        const row = this.codes.find(c => c.id === id);
        if (!row || row.type === 'hotp') throw new Error('Code unavailable');
        const otp = generateOTPs(row, this.offset)[0];
        const epoch = this.epoch;
        this.clipboard?.kill(); clearTimeout(this.clipboardTimer);
        await new Promise<void>((resolve, reject) => {
            // DMS's multi-offer transport preserves the sensitive hint and keeps
            // selection ownership in this child until lock or code expiry.
            const child = spawn('dms', ['cl', 'copy', '--foreground', '--type', '__multi__'], {
                stdio: ['pipe', 'pipe', 'ignore'], env: {...process.env, _DMS_CLIPBOARD_READY: '1'}
            });
            this.clipboard = child;
            let settled = false, probeTimer: any;
            const ackTimer = setTimeout(() => fail(new Error('Clipboard timed out')), 5000);
            const fail = (error: Error) => {
                if (settled) return;
                settled = true; clearTimeout(ackTimer); clearTimeout(probeTimer); child.kill(); reject(error);
            };
            child.on('error', fail);
            child.on('exit', () => {
                if (this.clipboard === child) this.clipboard = null;
                fail(new Error('Clipboard unavailable'));
            });
            child.stdin.on('error', fail);
            child.stdout.on('data', (data: Buffer) => {
                if (settled || !data.includes(1)) return;
                try { this.check(epoch); } catch (error: any) { fail(error); return; }
                settled = true; clearTimeout(ackTimer); clearTimeout(probeTimer); resolve();
            });
            child.on('spawn', () => {
                try { this.check(epoch); } catch (error: any) { fail(error); return; }
                child.stdin.end(clipboardOffers(Buffer.from(otp)), () => {
                    // DMS 1.6.2 serves multi-offers but predates the ready-byte
                    // handshake. Verify readiness through its native paste CLI.
                    const probe = () => {
                        if (settled) return;
                        execFile('dms', ['cl', 'paste'], {timeout: 1000, maxBuffer: 65536}, (error, value) => {
                            if (settled) return;
                            try { this.check(epoch); } catch (cancelled: any) { fail(cancelled); return; }
                            if (!error && value.trim() === otp) {
                                settled = true; clearTimeout(ackTimer); resolve();
                            } else probeTimer = setTimeout(probe, 50);
                        });
                    };
                    probeTimer = setTimeout(probe, 30);
                });
            });
            this.clipboardTimer = setTimeout(() => {
                if (this.clipboard === child) { child.kill(); this.clipboard = null; }
            }, getRemainingSeconds(row, this.offset) * 1000);
        });
        this.touch(); return {};
    }
}

export async function run() {
    process.umask(0o077);
    // Upstream diagnostics can include remote data: never forward them to shell logs.
    console.error = () => {};
    const originalFetch = globalThis.fetch;
    globalThis.fetch = (input, init) => originalFetch(input, {...init, signal: AbortSignal.timeout(20000)});
    const file = path.join(process.env.XDG_STATE_HOME || path.join(os.homedir(), '.local/state'), 'dms-ente-auth', 'vault.json');
    const vault = new Vault(file);
    const emit = (result: any) => process.stdout.write(JSON.stringify(result) + '\n');
    vault.onLock = () => emit({event: 'locked', state: vault.state()});
    try { await vault.init(); } catch { emit({event: 'error', error: 'storage_failed'}); }
    emit({event: 'ready', state: vault.state()});
    let busy = false;
    const input = readline.createInterface({input: process.stdin, terminal: false});
    input.on('line', async line => {
        let request: any;
        try {
            if (line.length > 16384) throw new Error();
            request = JSON.parse(line);
            const {action, params = {}, requestId} = request;
            // Lock remains responsive during remote requests and invalidates their results.
            if (action === 'lock') { emit({requestId, ok: true, state: vault.lock()}); return; }
            if (action === 'status') { emit({requestId, ok: true, state: vault.state()}); return; }
            if (action === 'touch') { vault.touch(); emit({requestId, ok: true}); return; }
            if (action === 'configure') { emit({requestId, ok: true, state: vault.configure(params)}); return; }
            if (busy) { emit({requestId, ok: false, error: 'busy'}); return; }
            busy = true;
            try {
                let state: any, rows: any, url: any;
                switch (action) {
                case 'login': state = await vault.loginStart(params.email, params.server); break;
                case 'password': state = await vault.password(params.password); break;
                case 'verify': state = await vault.verify(params.code); break;
                case 'passkey': url = vault.passkeyURL(); vault.touch(); break;
                case 'poll_passkey': state = await vault.pollPasskey(); break;
                case 'sync': state = await vault.sync(); break;
                case 'metadata': state = await vault.metadata(params); break;
                case 'otp_updates': rows = vault.updates(params.ids); break;
                case 'list': rows = vault.list(); break;
                case 'copy': await vault.copy(params.id); break;
                case 'logout': state = await vault.logout(); break;
                default: throw new Error('Unknown action');
                }
                emit({requestId, ok: true, state, rows, url});
            } catch (e: any) {
                const error = e.message === 'Operation cancelled' ? 'cancelled' : ['password', 'verify'].includes(action) ? 'auth_failed' : action === 'sync' ? 'sync_failed' : action === 'copy' ? 'clipboard_failed' : 'request_failed';
                emit({requestId, ok: false, error, state: vault.state()});
            } finally { busy = false; }
        } catch { emit({requestId: request?.requestId, ok: false, error: 'invalid_request'}); }
    });
    input.on('close', () => { vault.lock(); process.exit(0); });
    for (const signal of ['SIGTERM', 'SIGINT'] as const) process.on(signal, () => { vault.lock(); process.exit(0); });
}
if (process.argv[1] && process.argv[1] !== '-' && realpathSync(process.argv[1]) === fileURLToPath(import.meta.url)) run();
