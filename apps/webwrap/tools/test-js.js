'use strict';
// Execute the actual EXTRAS payload in a controlled page. These tests catch
// compatibility flags becoming global again, beyond a syntax-only check.
const fs = require('fs');
const vm = require('vm');
const assert = require('assert');
process.argv[2] = 'src/tv/webwrap/Main.java';
const { extract } = require('./check-js');
function page(strip, chat) {
  const timers = [];
  let removals = 0;
  const frame = { src: 'https://untrusted.example/player',
    hasAttribute: () => true, removeAttribute: () => removals++ };
  const document = { baseURI: 'https://site.example/',
    querySelectorAll: selector => selector === 'iframe,frame' ? [frame] : [] };
  const context = { window: { __wwStrip: strip, __wwChat: chat }, document,
    URL, console: { log() {} }, setInterval(fn, ms) { timers.push({ fn, ms }); return timers.length; } };
  vm.runInNewContext(extract('EXTRAS'), context);
  return { context, timers, removals: () => removals };
}
let p = page(false, false);
assert.strictEqual(p.timers.length, 0, 'disabled policies must not start recurring scans');
p.context.window.__wwSandbox();
assert.strictEqual(p.removals(), 0, 'disabled sandbox policy must never strip a frame');
p = page(false, true);
assert.deepStrictEqual(p.timers.map(t => t.ms), [1500], 'chat policy only starts chat timer');
p = page(true, false);
assert.deepStrictEqual(p.timers.map(t => t.ms), [1200]);
p.timers[0].fn();
assert.strictEqual(p.removals(), 0, 'unapproved frame must retain its sandbox');
console.log('behavior ok: feature gates and sandbox origin restrictions');
