// Reads every cricket ground in India from OpenStreetMap (free) and writes SQL
// that adds the new ones to the grounds table. Run by the "Import map grounds"
// workflow:  node scripts/import-map.mjs out.sql
import { writeFileSync } from 'node:fs';
import { mapGround } from '../src/grounds.js';

const SERVERS = [
  'https://overpass-api.de/api/interpreter',
  'https://overpass.private.coffee/api/interpreter',
  'https://maps.mail.ru/osm/tools/overpass/api/interpreter',
  'https://overpass.kumi.systems/api/interpreter',
];
const UA = 'GullyScore/0.9 (cricket scoring app; monthly grounds import)';
const filters = (where) => `(nwr["sport"~"cricket"]${where};nwr["leisure"~"^(pitch|stadium|sports_centre)$"]["name"~"[Cc]ricket"]${where};);out center tags;`;

async function ask(q, seconds) {
  for (const url of SERVERS) {
    try {
      const ac = new AbortController();
      const t = setTimeout(() => ac.abort(), seconds * 1000);
      const r = await fetch(url, { method: 'POST', headers: { 'content-type': 'application/x-www-form-urlencoded', 'user-agent': UA }, body: 'data=' + encodeURIComponent(q), signal: ac.signal });
      clearTimeout(t);
      if (!r.ok) {
        console.log(`${new URL(url).host}: ${r.status}`);
        continue;
      }
      const j = await r.json();
      if (j.remark && !(j.elements || []).length) {
        console.log(`${new URL(url).host}: ${j.remark.slice(0, 120)}`);
        continue;
      }
      console.log(`${new URL(url).host}: ${(j.elements || []).length} items`);
      return j.elements || [];
    } catch (e) {
      console.log(`${new URL(url).host}: ${e.name}`);
    }
  }
  return null;
}

let els = await ask(`[out:json][timeout:900];area["ISO3166-1"="IN"][admin_level=2]->.in;${filters('(area.in)')}`, 960);
if (els == null) {
  // Whole country did not work: go piece by piece.
  els = [];
  for (let lat = 6; lat < 37; lat += 3) {
    for (let lng = 68; lng < 98; lng += 3) {
      const part = await ask(`[out:json][timeout:180];${filters(`(${lat},${lng},${lat + 3},${lng + 3})`)}`, 200);
      if (part) els.push(...part);
      await new Promise((r) => setTimeout(r, 1500));
    }
  }
}

const q = (v) => `'${String(v).replace(/'/g, "''")}'`;
const seen = new Set();
const rows = [];
for (const e of els) {
  const g = mapGround(e);
  if (!g || seen.has(g.placeId)) continue;
  seen.add(g.placeId);
  const id = 'm' + e.type[0] + e.id; // the same ground always gets the same id
  rows.push(
    `INSERT OR IGNORE INTO grounds (id, name, address, city, lat, lng, place_id, pitches, facilities, timings, phone, user_id, created) SELECT ${q(id)}, ${q(g.name)}, ${q(g.address)}, ${q(g.city)}, ${g.lat}, ${g.lng}, ${q(g.placeId)}, ${q(JSON.stringify(g.pitches))}, ${q(JSON.stringify(g.facilities))}, ${q(g.timings)}, ${q(g.phone)}, '', ${Date.now()} WHERE NOT EXISTS (SELECT 1 FROM grounds WHERE place_id = ${q(g.placeId)});`,
  );
}
writeFileSync(process.argv[2] || 'map-grounds.sql', rows.join('\n') + '\n');
console.log(`::notice::Map grounds found in India: ${rows.length}`);
if (!rows.length) process.exit(1);
