import {Vault} from '../backend/dist/main.js';
import {execFileSync} from 'node:child_process';
const vault = new Vault('/dev/null');
vault.masterKey = 'synthetic';
vault.codes = [{id:'fixture',issuer:'Fixture',type:'totp',period:30,length:6,algorithm:'sha1',secret:'JBSWY3DPEHPK3PXP',codeDisplay:{},uriString:''}];
try {
 await vault.copy('fixture');
 let first;
 for(let i=0;i<20;i++) {
  try { first=execFileSync('wl-paste',['--no-newline','--type','text/plain'],{stdio:['ignore','pipe','ignore']}).toString(); break; } catch { await new Promise(r=>setTimeout(r,25)); }
 }
 const types=execFileSync('wl-paste',['--list-types'],{stdio:['ignore','pipe','ignore']}).toString();
 if (!types.includes('x-kde-passwordManagerHint')) throw new Error('Missing sensitive hint');
 const second=execFileSync('wl-paste',['--no-newline','--type','text/plain'],{stdio:['ignore','pipe','ignore']}).toString();
 if(!first || first!==second || !/^\d{6}$/.test(first) || !vault.clipboard || vault.clipboard.exitCode!==null) throw new Error('Clipboard regression');
 console.log('PASS: two successive Wayland reads return the test code; clipboard source remains alive with sensitive hint');
} finally { vault.lock(); }
