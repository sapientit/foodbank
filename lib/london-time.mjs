// London-time arithmetic for ./deploy, in Node so it is the same on macOS and
// Windows (the system `date` commands differ). Europe/London is the only local
// time zone; British Summer Time is handled by Intl, not by hand.
//
//   node lib/london-time.mjs next <HH:MM> <now epoch seconds>
//       the epoch second of the next HH:MM London time strictly after now
//   node lib/london-time.mjs format <epoch seconds>
//       e.g. "Fri 09 Oct 04:17 BST"
//   node lib/london-time.mjs stamp <epoch seconds>
//       e.g. "2026-10-09 04:17 BST" (used by the tests)

const zone = 'Europe/London';

function parts(ms) {
  const fields = new Intl.DateTimeFormat('en-GB', {
    timeZone: zone,
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
    second: '2-digit',
    hourCycle: 'h23',
  }).formatToParts(new Date(ms));
  const get = (type) => Number(fields.find((f) => f.type === type).value);
  return { y: get('year'), m: get('month'), d: get('day'), h: get('hour'), min: get('minute'), s: get('second') };
}

// The UTC instant at which London's clock shows the given wall-clock time.
function londonInstant(y, m, d, h, min) {
  let guess = Date.UTC(y, m - 1, d, h, min);
  for (let i = 0; i < 3; i += 1) {
    const p = parts(guess);
    const shown = Date.UTC(p.y, p.m - 1, p.d, p.h, p.min, p.s);
    guess += Date.UTC(y, m - 1, d, h, min) - shown;
  }
  return guess;
}

function next(hhmm, nowSeconds) {
  const [h, min] = hhmm.split(':').map(Number);
  const now = nowSeconds * 1000;
  const today = parts(now);
  for (let offset = 0; offset < 3; offset += 1) {
    const day = new Date(Date.UTC(today.y, today.m - 1, today.d + offset));
    const at = londonInstant(day.getUTCFullYear(), day.getUTCMonth() + 1, day.getUTCDate(), h, min);
    if (at > now) return Math.floor(at / 1000);
  }
  throw new Error('no next time found');
}

function zoneName(ms) {
  return new Intl.DateTimeFormat('en-GB', { timeZone: zone, timeZoneName: 'short' })
    .formatToParts(new Date(ms))
    .find((f) => f.type === 'timeZoneName')
    .value.replace(/^GMT\+1$/, 'BST');
}

const [command, a, b] = process.argv.slice(2);
if (command === 'next') {
  process.stdout.write(`${next(a, Number(b))}\n`);
} else if (command === 'format') {
  const ms = Number(a) * 1000;
  const text = new Intl.DateTimeFormat('en-GB', {
    timeZone: zone,
    weekday: 'short',
    day: '2-digit',
    month: 'short',
    hour: '2-digit',
    minute: '2-digit',
    hourCycle: 'h23',
  }).format(new Date(ms));
  process.stdout.write(`${text.replace(',', '')} ${zoneName(ms)}\n`);
} else if (command === 'stamp') {
  const ms = Number(a) * 1000;
  const p = parts(ms);
  const pad = (n) => String(n).padStart(2, '0');
  process.stdout.write(`${p.y}-${pad(p.m)}-${pad(p.d)} ${pad(p.h)}:${pad(p.min)} ${zoneName(ms)}\n`);
} else {
  process.stderr.write('usage: london-time.mjs next HH:MM NOW | format EPOCH | stamp EPOCH\n');
  process.exit(2);
}
