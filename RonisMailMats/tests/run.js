#!/usr/bin/env node
// Offline test runner for Roni's MailMats.
//
//   cd RonisMailMats/tests && npm install && npm test
//
// 1. Checks Data/Reagents.lua is up to date with RonisItemPedia's recipes.
// 2. Downloads (and caches) the WoW Forever client's API lists from
//    Ketho/BlizzardInterfaceResources (branch "forever").
// 3. Runs the addon in a Lua VM (fengari) against a mocked client
//    (wowmock.lua) and runs the specs in spec.lua. The mock may only define
//    functions that exist on Forever, so code relying on missing API fails.
"use strict";
const fs = require("fs");
const path = require("path");
const https = require("https");
const { execFileSync } = require("child_process");
const { lua, lauxlib, lualib, to_luastring, to_jsstring } = require("fengari");

const HERE = __dirname;
const ADDON_DIR = path.resolve(HERE, "..");
const CACHE = path.join(HERE, ".cache");
const API_BRANCH = "forever";
const API_FILES = ["GlobalAPI", "FrameXML"];

let failed = 0;

// --- 1. generated data ------------------------------------------------------
function checkReagents() {
  const gen = execFileSync(process.execPath, [path.join(ADDON_DIR, "tools", "gen_reagents.js")], { encoding: "utf8" });
  const have = fs.readFileSync(path.join(ADDON_DIR, "Data", "Reagents.lua"), "utf8").replace(/\r\n/g, "\n");
  if (gen !== have) {
    console.log("FAIL Data/Reagents.lua is stale: run node RonisMailMats/tools/gen_reagents.js > RonisMailMats/Data/Reagents.lua");
    failed++;
  } else {
    console.log("ok   Data/Reagents.lua matches the recipe database");
  }
}

// --- 2. Forever API lists ---------------------------------------------------
function fetch(url) {
  return new Promise((resolve, reject) => {
    https.get(url, { headers: { "User-Agent": "addon-tests" } }, (res) => {
      if (res.statusCode !== 200) { res.resume(); return reject(new Error(`${url}: HTTP ${res.statusCode}`)); }
      let body = "";
      res.setEncoding("utf8");
      res.on("data", (c) => (body += c));
      res.on("end", () => resolve(body));
    }).on("error", reject);
  });
}

async function loadApi() {
  fs.mkdirSync(CACHE, { recursive: true });
  const names = new Set();
  for (const f of API_FILES) {
    const file = path.join(CACHE, `${API_BRANCH}-${f}.lua`);
    if (!fs.existsSync(file) || process.env.REFRESH_API) {
      const url = `https://raw.githubusercontent.com/Ketho/BlizzardInterfaceResources/${API_BRANCH}/Resources/${f}.lua`;
      try {
        fs.writeFileSync(file, await fetch(url));
      } catch (e) {
        console.log(`warn could not download ${f}.lua (${e.message}); API checks skipped`);
        return null;
      }
    }
    for (const m of fs.readFileSync(file, "utf8").matchAll(/^\s*"([^"]+)",?\s*$/gm)) names.add(m[1]);
  }
  return names;
}

// --- 3. Lua -----------------------------------------------------------------
function runLua(apiNames) {
  const L = lauxlib.luaL_newstate();
  lualib.luaL_openlibs(L);

  lua.lua_pushjsfunction(L, (L) => {
    const p = to_jsstring(lauxlib.luaL_checkstring(L, 1));
    try {
      lua.lua_pushstring(L, fs.readFileSync(p));
      return 1;
    } catch (e) {
      lua.lua_pushnil(L);
      lua.lua_pushstring(L, to_luastring(e.message));
      return 2;
    }
  });
  lua.lua_setglobal(L, to_luastring("READFILE"));

  lua.lua_pushstring(L, to_luastring(ADDON_DIR.replace(/\\/g, "/")));
  lua.lua_setglobal(L, to_luastring("ADDON_DIR"));
  lua.lua_pushstring(L, to_luastring(HERE.replace(/\\/g, "/")));
  lua.lua_setglobal(L, to_luastring("TEST_DIR"));

  lua.lua_createtable(L, 0, 0);
  if (apiNames) {
    for (const n of apiNames) {
      lua.lua_pushstring(L, to_luastring(n));
      lua.lua_pushboolean(L, true);
      lua.lua_rawset(L, -3);
    }
    lua.lua_setglobal(L, to_luastring("FOREVER_API"));
  } else {
    lua.lua_pop(L, 1);
  }

  const src = fs.readFileSync(path.join(HERE, "harness.lua"));
  if (lauxlib.luaL_loadbuffer(L, src, null, to_luastring("@harness.lua")) !== lua.LUA_OK ||
      lua.lua_pcall(L, 0, 1, 0) !== lua.LUA_OK) {
    console.log("FAIL harness error: " + to_jsstring(lua.lua_tostring(L, -1)));
    return 1;
  }
  return lua.lua_tointeger(L, -1);
}

(async () => {
  checkReagents();
  const api = await loadApi();
  failed += runLua(api);
  console.log(failed === 0 ? "\nALL PASSED" : `\n${failed} FAILURE(S)`);
  process.exit(failed === 0 ? 0 : 1);
})();
