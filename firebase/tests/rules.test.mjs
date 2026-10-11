// Checks database.rules.json for the Ledger paths (ledger, ledgerCodes, ledgerGc)
// on the local emulator. From firebase/tests: npm ci && npm test
import { initializeTestEnvironment, assertFails, assertSucceeds } from '@firebase/rules-unit-testing';
import fs from 'fs';
const TS = { '.sv': 'timestamp' };
const env = await initializeTestEnvironment({ projectId: 'demo-x', database: { rules: fs.readFileSync(new URL('../database.rules.json', import.meta.url), 'utf8'), host: '127.0.0.1', port: 9000 } });
const db = (u) => env.authenticatedContext(u).database();
const anon = env.unauthenticatedContext().database();
let pass = 0, fail = 0;
async function ok(name, p) { try { await assertSucceeds(p); pass++; } catch (e) { fail++; console.log('FAIL (should succeed):', name, e.message); } }
async function no(name, p) { try { await assertFails(p); pass++; } catch (e) { fail++; console.log('FAIL (should be denied):', name, e.message); } }
const A = db('alice'), B = db('bob'), C = db('carol'), D = db('dave');
const id = 'L1', code = 'ABCD2345';
const create = (u, id, code) => ({ [`ledger/${id}/meta`]: { a: 'Rahul', b: 'Amit', code, created: TS }, [`ledger/${id}/members/${u}`]: { s: 'a' }, [`ledgerCodes/${code}`]: { id, a: 'Rahul', b: 'Amit' }, [`ledgerUsers/${u}/ledgers/${id}`]: 'a' });
const entry = (by, amt, extra = {}) => ({ amt, by, date: 1700000000000, tag: 'Food', note: 'Lunch', at: TS, cs: by, ...extra });

await no('anon create', anon.ref().update(create('x', id, code)));
await ok('create', A.ref().update(create('alice', id, code)));
await no('create over existing code', C.ref().update(create('carol', 'L9', code)));
await no('create with mismatched code', C.ref().update({ ...create('carol', 'L8', 'ZZZZ2345'), ['ledgerCodes/ZZZZ2345']: { id: 'L1', a: 'x', b: 'y' } }));
await no('carol hijacks meta', C.ref().update({ [`ledger/${id}/meta`]: { a: 'X', b: 'Y', code: 'QQQQ2345', created: TS }, [`ledger/${id}/members/carol`]: { s: 'a' } }));
await ok('bob looks up code', B.ref(`ledgerCodes/${code}`).get());
await no('bob lists codes', B.ref('ledgerCodes').get());
await no('bob reads log before join', B.ref(`ledger/${id}`).get());
await no('bob joins with wrong code', B.ref().update({ [`ledger/${id}/members/bob`]: { s: 'b', c: 'WRNG2345' } }));
await no('bob joins without code', B.ref().update({ [`ledger/${id}/members/bob`]: { s: 'b' } }));
await no('bob adds someone else', B.ref().update({ [`ledger/${id}/members/eve`]: { s: 'b', c: code } }));
await ok('bob joins', B.ref().update({ [`ledger/${id}/members/bob`]: { s: 'b', c: code }, [`ledgerUsers/bob/ledgers/${id}`]: 'b' }));
await ok('bob reads log', B.ref(`ledger/${id}`).get());
await no('carol reads log', C.ref(`ledger/${id}`).get());
await no('bob bad side', B.ref().update({ [`ledger/${id}/members/bob/s`]: 'c' }));
await ok('bob switches side and back', B.ref().update({ [`ledger/${id}/members/bob/s`]: 'a' }));
await ok('bob back', B.ref().update({ [`ledger/${id}/members/bob/s`]: 'b' }));

await ok('bob adds entry', B.ref().update({ [`ledger/${id}/entries/e1`]: entry('b', 50000) }));
await ok('alice adds entry', A.ref().update({ [`ledger/${id}/entries/e2`]: entry('a', 20000) }));
await no('carol adds entry', C.ref().update({ [`ledger/${id}/entries/e3`]: entry('a', 100) }));
await no('zero amount', A.ref().update({ [`ledger/${id}/entries/e3`]: entry('a', 0) }));
await no('negative amount', A.ref().update({ [`ledger/${id}/entries/e3`]: entry('a', -5) }));
await no('fraction amount', A.ref().update({ [`ledger/${id}/entries/e3`]: entry('a', 10.5) }));
await no('huge amount', A.ref().update({ [`ledger/${id}/entries/e3`]: entry('a', 100000000001) }));
await ok('max amount', A.ref().update({ [`ledger/${id}/entries/e4`]: entry('a', 100000000000) }));
await ok('delete entry', A.ref().update({ [`ledger/${id}/entries/e4`]: null }));
await no('bad by', A.ref().update({ [`ledger/${id}/entries/e3`]: entry('c', 100) }));
await no('extra field', A.ref().update({ [`ledger/${id}/entries/e3`]: entry('a', 100, { x: 1 }) }));
await no('long note', A.ref().update({ [`ledger/${id}/entries/e3`]: entry('a', 100, { note: 'x'.repeat(201) }) }));
await no('fake created time', A.ref().update({ [`ledger/${id}/entries/e3`]: entry('a', 100, { at: 5 }) }));
await ok('bob edits alice entry', B.ref().update({ [`ledger/${id}/entries/e2`]: { ...entry('a', 25000), at: (await A.ref(`ledger/${id}/entries/e2/at`).get()).val(), cs: 'a', ea: TS, es: 'b' } }));
await no('bob edits pretending to be a', B.ref().update({ [`ledger/${id}/entries/e2`]: { ...entry('a', 25000), at: (await A.ref(`ledger/${id}/entries/e2/at`).get()).val(), cs: 'a', ea: TS, es: 'a' } }));

const appr = (sig) => ({ sig, net: -25000, at: TS });
await ok('alice confirms', A.ref().update({ [`ledger/${id}/ok/a`]: appr('2.-25000.abc') }));
await no('alice confirms for bob', A.ref().update({ [`ledger/${id}/ok/b`]: appr('2.-25000.abc') }));
await no('done with one confirm', A.ref().update({ [`ledger/${id}/done`]: TS }));
await ok('edit clears confirmations', B.ref().update({ [`ledger/${id}/entries/e1/note`]: 'Dinner', [`ledger/${id}/ok`]: null }));
await ok('alice confirms again', A.ref().update({ [`ledger/${id}/ok/a`]: appr('S1') }));
await no('bob confirms other version and clears', B.ref().update({ [`ledger/${id}/ok/b`]: appr('S2'), [`ledger/${id}/done`]: TS, [`ledgerGc/${id}`]: { t: TS } }));
await ok('bob confirms and clears', B.ref().update({ [`ledger/${id}/ok/b`]: appr('S1'), [`ledger/${id}/done`]: TS, [`ledgerGc/${id}`]: { t: TS }, [`ledgerCodes/${code}`]: null, [`ledger/${id}/meta/code`]: null }));
await no('dave joins cleared log with old code', D.ref().update({ [`ledger/${id}/members/dave`]: { s: 'b', c: code } }));
await no('dave joins cleared log without code', D.ref().update({ [`ledger/${id}/members/dave`]: { s: 'b' } }));
await no('entry after cleared', A.ref().update({ [`ledger/${id}/entries/e5`]: entry('a', 100) }));
await no('edit after cleared', A.ref().update({ [`ledger/${id}/entries/e1/amt`]: 1 }));
await no('confirm after cleared', A.ref().update({ [`ledger/${id}/ok/a`]: appr('S3') }));
await no('fake done time', A.ref().update({ [`ledger/${id}/done`]: 5 }));
await no('carol deletes before expiry', C.ref().update({ [`ledger/${id}`]: null, [`ledgerGc/${id}`]: null, [`ledgerCodes/${code}`]: null }));
await no('alice deletes before expiry', A.ref().update({ [`ledger/${id}`]: null, [`ledgerGc/${id}`]: null, [`ledgerCodes/${code}`]: null }));
await no('carol deletes gc entry', C.ref().update({ [`ledgerGc/${id}`]: null }));
await ok('reopen with new code', A.ref().update({ [`ledger/${id}/done`]: null, [`ledger/${id}/ok`]: null, [`ledgerGc/${id}`]: null, [`ledgerCodes/${code}`]: { id, a: 'Rahul', b: 'Amit' }, [`ledger/${id}/meta/code`]: code }));
await no('carol deletes code', C.ref().update({ [`ledgerCodes/${code}`]: null }));
await ok('entry after reopen', A.ref().update({ [`ledger/${id}/entries/e5`]: entry('a', 100) }));

// Reset code
const code2 = 'WXYZ6789';
await no('carol resets code', C.ref().update({ [`ledgerCodes/${code}`]: null, [`ledgerCodes/${code2}`]: { id, a: 'Rahul', b: 'Amit' }, [`ledger/${id}/meta/code`]: code2 }));
await ok('alice resets code', A.ref().update({ [`ledgerCodes/${code}`]: null, [`ledgerCodes/${code2}`]: { id, a: 'Rahul', b: 'Amit' }, [`ledger/${id}/meta/code`]: code2 }));
await ok('bob still reads', B.ref(`ledger/${id}/entries`).get());
await no('dave joins with old code', D.ref().update({ [`ledger/${id}/members/dave`]: { s: 'b', c: code } }));
await ok('dave joins with new code', D.ref().update({ [`ledger/${id}/members/dave`]: { s: 'b', c: code2 } }));
await ok('rename', A.ref().update({ [`ledger/${id}/meta/b`]: 'Amit K', [`ledgerCodes/${code2}/b`]: 'Amit K' }));
await no('carol renames', C.ref().update({ [`ledgerCodes/${code2}/b`]: 'Hacked' }));
await no('carol points code elsewhere', C.ref().update({ [`ledgerCodes/${code2}/id`]: 'L2' }));
await no('alice deletes non-empty open log', A.ref().update({ [`ledger/${id}`]: null }));
await ok('dave leaves', D.ref().update({ [`ledger/${id}/members/dave`]: null }));
await no('dave reads after leaving', D.ref(`ledger/${id}`).get());
await no('alice removes bob', A.ref().update({ [`ledger/${id}/members/bob`]: null }));

// GC queries
const now = Date.now();
await ok('gc query old', C.ref('ledgerGc').orderByChild('t').endAt(now - 1209600000 - 60000).limitToFirst(20).get());
await no('gc query too many', C.ref('ledgerGc').orderByChild('t').endAt(now - 1309600000).limitToFirst(50).get());
await no('gc by key', C.ref('ledgerGc').orderByKey().limitToFirst(20).get());
await no('gc plain read', C.ref('ledgerGc').get());

// Expired: settle, then age it with rules off.
await ok('settle a', A.ref().update({ [`ledger/${id}/ok/a`]: appr('S9') }));
await ok('settle b', B.ref().update({ [`ledger/${id}/ok/b`]: appr('S9'), [`ledger/${id}/done`]: TS, [`ledgerGc/${id}`]: { t: TS }, [`ledgerCodes/${code2}`]: null, [`ledger/${id}/meta/code`]: null }));
const old = now - 15 * 86400000;
await env.withSecurityRulesDisabled(async (ctx) => { await ctx.database().ref().update({ [`ledger/${id}/done`]: old, [`ledgerGc/${id}/t`]: old }); });
const found = await C.ref('ledgerGc').orderByChild('t').endAt(now - 1209600000 - 60000).limitToFirst(20).get();
if (!found.hasChild(id)) { fail++; console.log('FAIL: gc did not find expired'); } else pass++;
await no('carol gc entry only while log exists', C.ref().update({ [`ledgerGc/${id}`]: null }));
await ok('carol cleans expired', C.ref().update({ [`ledger/${id}`]: null, [`ledgerGc/${id}`]: null }));
await env.withSecurityRulesDisabled(async (ctx) => { const all = (await ctx.database().ref().get()).val() || {}; const v = all.ledger || all.ledgerCodes || all.ledgerGc; if (v) { fail++; console.log('FAIL: leftovers', JSON.stringify(v)); } else pass++; });

// Empty log delete
await ok('create 2', A.ref().update(create('alice', 'L2', 'EMPT2345')));
await no('bob deletes empty log he is not in', B.ref().update({ ['ledger/L2']: null, ['ledgerCodes/EMPT2345']: null }));
await ok('alice deletes empty log', A.ref().update({ ['ledger/L2']: null, ['ledgerGc/L2']: null, ['ledgerCodes/EMPT2345']: null }));
// Account index
await ok('bob writes own index', B.ref().update({ ['ledgerUsers/bob/ledgers/L1']: 'b' }));
await ok('bob reads own index', B.ref('ledgerUsers/bob').get());
await no('carol reads bob index', C.ref('ledgerUsers/bob').get());
await no('carol writes bob index', C.ref().update({ ['ledgerUsers/bob/ledgers/L9']: 'a' }));
await no('bad side in index', B.ref().update({ ['ledgerUsers/bob/ledgers/L2']: 'x' }));
await no('extra field in index', B.ref().update({ ['ledgerUsers/bob/other']: 1 }));
await no('list all users', C.ref('ledgerUsers').get());
await ok('bob clears own entry', B.ref().update({ ['ledgerUsers/bob/ledgers/L1']: null }));
// Feed reports (Vacancy Bell, Roz Quiz): write-once, never readable from apps
const rep = (by, extra = {}) => ({ app: 'vacancy_bell', item: 'ssc-cgl-2026-abc123', reason: 'wrong_date', note: 'Last date is 6 Oct', by, at: TS, ...extra });
await ok('report', A.ref('feedReports/r1').set(rep('alice')));
await ok('quiz report without note', A.ref('feedReports/r2').set({ app: 'roz_quiz', item: 'q-gk-1', reason: 'wrong_answer', by: 'alice', at: TS }));
await no('anon report', anon.ref('feedReports/r3').set(rep('x')));
await no('report as someone else', A.ref('feedReports/r3').set(rep('bob')));
await no('overwrite report', B.ref('feedReports/r1').set(rep('bob')));
await no('delete report', A.ref('feedReports/r1').remove());
await no('unknown app', A.ref('feedReports/r3').set(rep('alice', { app: 'other' })));
await no('unknown reason', A.ref('feedReports/r3').set(rep('alice', { reason: 'spam' })));
await no('long note', A.ref('feedReports/r3').set(rep('alice', { note: 'x'.repeat(301) })));
await no('empty item', A.ref('feedReports/r3').set(rep('alice', { item: '' })));
await no('fake time', A.ref('feedReports/r3').set(rep('alice', { at: 5 })));
await no('extra field', A.ref('feedReports/r3').set(rep('alice', { x: 1 })));
await no('missing reason', A.ref('feedReports/r3').set({ app: 'roz_quiz', item: 'q', by: 'alice', at: TS }));
await no('read reports', A.ref('feedReports').get());
await no('read own report', A.ref('feedReports/r1').get());
console.log(`passed ${pass}, failed ${fail}`);
await env.cleanup();
process.exit(fail ? 1 : 0);
