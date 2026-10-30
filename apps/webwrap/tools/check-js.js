#!/usr/bin/env node
// Syntax-check the JS payloads embedded in Main.java before they are baked
// into the dex. One missing quote in a Java string concat produced
// "Unexpected token '>'" on the TV and silently killed the whole EXTRAS
// payload (chat hide, frame-pin, everything) — so gate it here.
//
// Usage: node tools/check-js.js src/tv/webwrap/Main.java [dump-dir]
'use strict';
const fs = require('fs');

const src = fs.readFileSync(process.argv[2], 'utf8');

function extract(name) {
  const start = src.indexOf(`private static final String ${name} =`);
  if (start < 0) throw new Error(`block ${name} not found`);
  const end = src.indexOf('+ "})()";', start);
  if (end < 0) throw new Error(`end of ${name} not found`);
  const block = src.slice(start, end + 9);
  let js = '';
  for (const line of block.split('\n')) {
    const t = line.trim();
    if (t.startsWith('//')) continue;          // full-line comment
    if (t.startsWith('private')) continue;
    const lits = t.match(/"(?:\\.|[^"\\])*"/g) || [];
    for (const l of lits) {
      js += l
        .slice(1, -1)
        .replace(/\\"/g, '"')
        .replace(/\\'/g, "'")
        .replace(/\\\\/g, '\\')
        .replace(/\\n/g, '\n')
        .replace(/\\t/g, '\t');
    }
  }
  return js;
}

let bad = 0;
const dumpDir = process.argv[3];
for (const name of ['EXTRAS', 'POINTER']) {
  const js = extract(name);
  if (dumpDir) fs.writeFileSync(`${dumpDir}/${name}.js`, js);
  try {
    // jshint-disable-line: IIFE expression — runs nothing, parse only
    new Function(js);
    console.log(`js ok: ${name} (${js.length} chars)`);
  } catch (e) {
    bad = 1;
    console.error(`js SYNTAX ERROR in ${name}: ${e.message}`);
    const around = js.slice(0, 400);
    console.error(`--- head ---\n${around}\n--- end head ---`);
  }
}
if (require.main === module) process.exitCode = bad;
module.exports = { extract };
