#!/usr/bin/env node
// Holds the Play listing in copy/ and declarations/ to the limits the Play Console enforces only
// at paste time, and to the listing rules this app has to keep.
//
//   node android/store/check.js        # from the repo root; exits 1 on any problem
//
// Counts are in code points rather than UTF-16 units: Play documents its caps in Unicode
// characters, and an emoji would otherwise count twice.
const fs = require('node:fs');
const path = require('node:path');

const COPY_DIR = path.join(__dirname, 'copy');
const DECLARATIONS_DIR = path.join(__dirname, 'declarations');
const SCREENSHOTS_DIR = path.join(__dirname, 'play', 'screenshots');

/** One row per copy file, with the Play field it feeds and that field's cap. */
const FIELDS = [
  { file: 'name', max: 30, min: 2, field: 'App name' },
  { file: 'play-short-description', max: 80, min: 10, field: 'Short description' },
  { file: 'description', max: 4000, min: 10, field: 'Full description' },
  { file: 'release-notes', max: 500, min: 2, field: "Release notes (What's new)" },
  // App access has no published cap; it is checked for house style and its placeholders.
  { file: 'play-app-access-instructions', max: Infinity, min: 2, field: 'App access instructions' }
];

/** House style. */
const BANNED = [
  { pattern: /[\u2014\u2013]/, label: 'em or en dash' },
  { pattern: /[\u2018\u2019\u201c\u201d]/, label: 'smart quote' },
  { pattern: /\t/, label: 'tab' }
];

/**
 * Listing rules. Play's metadata policy bars price and ranking claims, and Seam's own rule is
 * that the title and short description name no other company's product: networks appear only
 * in the full description, as examples of bridges the user runs, with no affiliation implied.
 * The listing also never recommends a server or a bridge, and never names Apple's or Google's
 * messaging products, the two the legal review singles out.
 */
const RANKING = /\b(free|best|top|new|#1|number one)\b/i;
const NETWORKS =
  /\b(imessage|google messages|whatsapp|telegram|signal|discord|linkedin|xbox|instagram|messenger|facebook|slack|sms)\b/i;
const NEVER = /\b(imessage|apple|google messages|fluffychat\.im|matrix\.org)\b/i;

const problems = [];
const read = (dir, name) => fs.readFileSync(path.join(dir, name), 'utf8').trim();
const count = (text) => Array.from(text).length;
const lines = (text) => text.split('\n').map((line) => line.trim()).filter(Boolean);
const banned = (text, name) => {
  for (const { pattern, label } of BANNED) {
    if (pattern.test(text)) problems.push(`${name} contains a ${label}`);
  }
};

for (const { file, max, min, field } of FIELDS) {
  const text = read(COPY_DIR, `${file}.txt`);
  const length = count(text);
  if (length > max) problems.push(`${file}.txt is ${length} characters, over the ${max} Play allows for ${field}`);
  if (length < min) problems.push(`${file}.txt is ${length} characters, under the ${min} ${field} needs`);
  banned(text, `${file}.txt`);
}

for (const file of ['name', 'play-short-description', 'description', 'release-notes']) {
  const text = read(COPY_DIR, `${file}.txt`);
  const ranking = RANKING.exec(text);
  if (ranking) problems.push(`${file}.txt contains "${ranking[0]}", a price or ranking word Play bars`);
  const never = NEVER.exec(text);
  if (never) problems.push(`${file}.txt names "${never[0]}", which the listing never names`);
}
for (const file of ['name', 'play-short-description', 'release-notes']) {
  const hit = NETWORKS.exec(read(COPY_DIR, `${file}.txt`));
  if (hit) problems.push(`${file}.txt names "${hit[0]}"; networks belong only in description.txt, as examples`);
}

// Where the description names networks, it has to say in the same text that Seam is not
// affiliated with them and does not include the bridges.
const description = read(COPY_DIR, 'description.txt');
if (NETWORKS.test(description) && !/not affiliated/i.test(description)) {
  problems.push('description.txt names other networks without saying Seam is not affiliated with them');
}
// AGPL section 6: the place that offers the binary says where the source is.
if (!description.includes('https://github.com/GraysonCAdams/fluffychat')) {
  problems.push('description.txt has lost the link to the source code');
}

// One alt text line for the feature graphic, then one per committed phone screenshot, in order.
const ALT_TEXT_MAX = 140;
const altTextRaw = read(COPY_DIR, 'play-alt-text.txt');
const altText = lines(altTextRaw);
banned(altTextRaw, 'play-alt-text.txt');
altText.forEach((line, index) => {
  if (count(line) > ALT_TEXT_MAX) {
    problems.push(`play-alt-text.txt line ${index + 1} is ${count(line)} characters, over Play's ${ALT_TEXT_MAX}`);
  }
});
const screenshots = fs.existsSync(SCREENSHOTS_DIR)
  ? fs.readdirSync(SCREENSHOTS_DIR).filter((name) => /\.(png|jpe?g)$/i.test(name))
  : [];
if (altText.length !== 1 + screenshots.length) {
  problems.push(
    `play-alt-text.txt has ${altText.length} lines; it needs one for the feature graphic and one for each of the ${screenshots.length} screenshots`
  );
}

// The review account's details are pasted into the console by hand and never committed.
const access = read(COPY_DIR, 'play-app-access-instructions.txt');
for (const placeholder of ['{{REVIEW_USER}}', '{{REVIEW_PASSWORD}}', '{{RECOVERY_KEY}}', '{{PARTNER_USER}}']) {
  if (!access.includes(placeholder)) {
    problems.push(`play-app-access-instructions.txt no longer carries the ${placeholder} placeholder`);
  }
}

// Play allows five tags and takes them from its own list, which this cannot see.
const tags = lines(read(DECLARATIONS_DIR, 'play-tags.txt'));
if (tags.length < 1 || tags.length > 5) {
  problems.push(`declarations/play-tags.txt has ${tags.length} tags; Play takes one to five`);
}
if (new Set(tags).size !== tags.length) problems.push('declarations/play-tags.txt repeats a tag');

if (problems.length > 0) {
  console.error('Store listing problems:');
  for (const problem of problems) console.error(`  - ${problem}`);
  process.exit(1);
}
console.log(
  `Store listing is within every limit (${FIELDS.length} fields, ${altText.length} alt texts, ${tags.length} tags).`
);
