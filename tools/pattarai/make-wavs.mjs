#!/usr/bin/env node
// Makes the WAV of every Isai song in a game's music folder that needs one,
// as Isai's "Make all WAVs" does: for automatic builds, and for anyone who
// keeps only the songs (music/*.json) and not their WAVs.
//
//   node tools/pattarai/make-wavs.mjs <game folder> [--all]
//
// --all makes every song's WAV again, needed or not. Needs node 18 or newer.
import { readFileSync, writeFileSync, existsSync, readdirSync } from "fs";
import { join } from "path";
import { songWav, madeNote, refreshNote, needsWav } from "./lib/make.js";

const args = process.argv.slice(2);
const game = args.find((a) => !a.startsWith("--"));
if (!game) { console.error("usage: node tools/pattarai/make-wavs.mjs <game folder> [--all]"); process.exit(2); }
const folder = join(game, "music");
if (!existsSync(folder)) { console.log("no music folder: nothing to make"); process.exit(0); }
let made = 0, failed = 0;
for (const file of readdirSync(folder).filter((f) => f.endsWith(".json")).sort()) {
  const songPath = join(folder, file), wavPath = songPath.replace(/\.json$/, ".wav");
  let song;
  try { song = JSON.parse(readFileSync(songPath, "utf8")); } catch (e) { console.error(`${file}: not JSON (${e.message})`); failed++; continue; }
  if (song.format !== "isai-song") continue;
  await refreshNote(song);
  const why = args.includes("--all") ? "--all" : needsWav(song, existsSync(wavPath));
  if (!why) continue;
  const t = Date.now();
  try {
    const wav = songWav(song);
    writeFileSync(wavPath, wav);
    song.made = await madeNote(song, wav);
    writeFileSync(songPath, JSON.stringify(song, null, 1) + "\n");
    console.log(`made music/${file.replace(/\.json$/, ".wav")} (${why}; ${((Date.now() - t) / 1000).toFixed(1)} s)`);
    made++;
  } catch (e) { console.error(`${file}: ${e.message}`); failed++; }
}
console.log(`${made} made${failed ? `, ${failed} failed` : ""}`);
process.exit(failed ? 1 : 0);
