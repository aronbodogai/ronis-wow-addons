#!/usr/bin/env node
// Generates RonisMailMats/Data/Crates.lua: which profession each Waylaid
// Supplies / Waylaid Crate item should be mailed to.
//
// A crate asks for crafted goods or raw materials. It goes to the profession
// that crafts what it asks for (RonisItemPedia's recipe database); for a raw
// material nobody crafts (Linen Cloth, Peacebloom, Copper Ore) to the
// profession that uses it in the most recipes.
//
//   Waylaid Supplies: the item's use spell has the requested item as reagent
//                     (SpellReagents).
//   Waylaid Crate:    the use spell's description lists the bundles,
//                     "- $M3 Bolt of Woolen Cloth"; names are matched to items.
//
// Usage (from the AddOns folder):
//   node RonisMailMats/tools/gen_crates.js <csv-dir> <build> > RonisMailMats/Data/Crates.lua
// Needed tables (https://wago.tools/db2/<Table>/csv?build=<build>):
//   Item, ItemSparse, ItemXItemEffect, ItemEffect, SpellReagents, Spell
"use strict";
const fs = require("fs");
const path = require("path");

const [dir, build] = process.argv.slice(2);
if (!dir || !build) {
  console.error("usage: gen_crates.js <csv-dir> <build>");
  process.exit(1);
}

function parseCSV(text) {
  const rows = [];
  let row = [], field = "", quoted = false;
  for (let i = 0; i < text.length; i++) {
    const c = text[i];
    if (quoted) {
      if (c === '"') {
        if (text[i + 1] === '"') { field += '"'; i++; } else quoted = false;
      } else field += c;
    } else if (c === '"') quoted = true;
    else if (c === ",") { row.push(field); field = ""; }
    else if (c === "\n") { row.push(field.replace(/\r$/, "")); rows.push(row); row = []; field = ""; }
    else field += c;
  }
  if (field || row.length) { row.push(field); rows.push(row); }
  const head = rows.shift();
  return rows.filter((r) => r.length > 1).map((r) => Object.fromEntries(head.map((k, i) => [k, r[i]])));
}
const read = (t) => parseCSV(fs.readFileSync(path.join(dir, t + ".csv"), "utf8"));

// --- recipe database: who crafts what, who uses what -------------------------
const recipesText = fs.readFileSync(
  path.join(__dirname, "..", "..", "RonisItemPedia", "Data", "Recipes.lua"), "utf8");
const profs = JSON.parse("[" + recipesText.match(/ns\.RECIPE_PROFS = \{([^}]*)\}/)[1] + "]");
const makers = new Map(); // item -> Set(prof)
const uses = new Map();   // item -> Map(prof -> recipe count)
const re = /^\s*\{(\d+),(\d+),(\d+),(\d+),(\d+),\{([\d,]*)\}(?:,[\d,]*,\{[\d,]*\})?\},?\s*$/gm;
let m;
while ((m = re.exec(recipesText))) {
  const prof = profs[Number(m[2]) - 1];
  const product = Number(m[3]);
  if (product) (makers.get(product) || makers.set(product, new Set()).get(product)).add(prof);
  const r = m[6].split(",").filter(Boolean).map(Number);
  for (let i = 0; i < r.length; i += 2) {
    const u = uses.get(r[i]) || uses.set(r[i], new Map()).get(r[i]);
    u.set(prof, (u.get(prof) || 0) + 1);
  }
}

// Item type first: raw and intermediate goods have an obvious home.
//   Tradeskill (7): parts/explosives/devices -> Engineering, cloth -> Tailoring,
//   leather -> Leatherworking, metal & stone -> Mining, meat -> Cooking,
//   herbs -> Alchemy, enchanting -> Enchanting.
//   Consumable (0): potions/elixirs/flasks -> Alchemy, food -> Cooking,
//   bandages -> First Aid.
const BY_TYPE = {
  "7/1": "Engineering", "7/2": "Engineering", "7/3": "Engineering", "7/5": "Tailoring",
  "7/6": "Leatherworking", "7/7": "Mining", "7/8": "Cooking", "7/9": "Alchemy", "7/12": "Enchanting",
  "0/1": "Alchemy", "0/2": "Alchemy", "0/3": "Alchemy", "0/5": "Cooking", "0/7": "First Aid",
};
let itemType = new Map(); // filled from Item.csv below

// Professions an item points to: by type, else its crafters, else its biggest user.
function profsFor(item) {
  const t = BY_TYPE[itemType.get(String(item))];
  if (t) return [t];
  if (makers.has(item)) return [...makers.get(item)];
  const u = uses.get(item);
  if (!u) return [];
  let best = null, n = -1;
  for (const [p, c] of u) if (c > n) { best = p; n = c; }
  return [best];
}

// --- client data ---------------------------------------------------------------
const items = read("ItemSparse");
itemType = new Map(read("Item").map((i) => [i.ID, i.ClassID + "/" + i.SubclassID]));
const byId = new Map(items.map((i) => [i.ID, i]));
const byName = new Map(); // name -> lowest item id that is not a test item
for (const i of items) {
  if (/^(Deprecated|\[DNT\]|Test )/i.test(i.Display_lang)) continue;
  const prev = byName.get(i.Display_lang);
  if (!prev || Number(i.ID) < Number(prev)) byName.set(i.Display_lang, i.ID);
}
const effectsOf = new Map();
const effect = new Map(read("ItemEffect").map((e) => [e.ID, e]));
for (const x of read("ItemXItemEffect")) {
  const e = effect.get(x.ItemEffectID);
  if (e) (effectsOf.get(x.ItemID) || effectsOf.set(x.ItemID, []).get(x.ItemID)).push(e.SpellID);
}
const reagents = new Map(read("SpellReagents").map((r) => [r.SpellID, r]));
const desc = new Map(read("Spell").map((s) => [s.ID, s.Description_lang || ""]));

// Item from a plural crate name: "Goblin Mortars", "Elixirs of Agility",
// "Silver Skeleton Keys", "Heavy Hide" (already singular).
function FromName(plural) {
  const tries = [plural];
  const sing = (w) => w.replace(/ies$/, "y").replace(/(ch|sh|x)es$/, "$1").replace(/s$/, "");
  tries.push(plural.replace(/(\S+)$/, sing));                // last word: Mortars -> Mortar
  tries.push(plural.replace(/^(\S+)( of .*)$/, (_, a, b) => sing(a) + b)); // Elixirs of X
  for (const t of tries) if (byName.has(t)) return byName.get(t);
  return null;
}

const crates = [];
const problems = [];
for (const it of items) {
  if (!/^Waylaid (Supplies|Crate): /.test(it.Display_lang)) continue;
  const wants = new Set();
  // "Waylaid Supplies: Goblin Mortars" asks for Goblin Mortar: the name is
  // the surest guide (some fill spells list an unrelated reagent)
  const named = it.Display_lang.startsWith("Waylaid Supplies: ") && FromName(it.Display_lang.slice(18));
  if (named) wants.add(named);
  for (const spell of effectsOf.get(it.ID) || []) {
    const r = reagents.get(spell);
    if (r && !named) for (let k = 0; k < 8; k++) if (r["Reagent_" + k] && r["Reagent_" + k] !== "0") wants.add(r["Reagent_" + k]);
    for (const line of (desc.get(spell) || "").split("\n")) {
      const lm = line.match(/^-\s*\$M\d+\s+(.+?)\s*$/);
      if (!lm) continue;
      const name = lm[1].replace(/\|c[0-9a-fA-F]{8}/g, "").replace(/\|r/g, "").trim(); // color codes
      const id = byName.get(name);
      if (id) wants.add(id); else problems.push(`${it.Display_lang}: no item named "${name}"`);
    }
  }
  const to = new Set();
  for (const w of wants) for (const p of profsFor(Number(w))) to.add(p);
  if (to.size === 0) { problems.push(`${it.Display_lang}: no profession`); continue; }
  crates.push({ id: Number(it.ID), name: it.Display_lang, to: [...to].sort(),
                wants: [...wants].map((w) => byId.get(w)?.Display_lang || w) });
}
if (problems.length) console.error("warnings:\n  " + problems.join("\n  "));

crates.sort((a, b) => a.id - b.id);
const lines = [
  "-- Generated by tools/gen_crates.js from the client's ItemSparse, ItemXItemEffect, ItemEffect,",
  `-- SpellReagents and Spell tables (build ${build}) and RonisItemPedia's recipes. Do not edit by hand.`,
  "-- CRATES[itemID] = { professions it goes to }: the crafters of what it asks for, or for raw",
  "-- materials the profession using them in the most recipes.",
  "local _, ns = ...",
  "ns.CRATES = {",
];
for (const c of crates) {
  lines.push(`    [${c.id}] = {${c.to.map((p) => JSON.stringify(p)).join(", ")}}, -- ${c.name}: ${c.wants.join(", ")}`);
}
lines.push("}");
process.stdout.write(lines.join("\n") + "\n");
