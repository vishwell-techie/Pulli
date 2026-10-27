// Making a song's WAV, and the note a song keeps about it. Used by Isai and
// by make-wavs.mjs, so the browser and node make the same file.
//
// A song saved with its WAV carries `made`: the engine that made the WAV
// (music.js ENGINE), the WAV's SHA-256, the SHA-256 of the song as it was
// then, and `current`, whether the song is still as it was when the WAV
// was made. pulli pack reads it: a song with no WAV stops the pack (music(n)
// counts the WAV files, so a missing one would move every track after it);
// a song changed since, or made by an older engine, is said.
import * as M from "./music.js";
import { encodeWAV } from "./wav.js";

// a mono song is both sides together, each at half
export function wavOf(song, [L, R]) {
  let chans = [L, R];
  if (song.mono) {
    const m = new Float32Array(L.length);
    for (let i = 0; i < m.length; i++) m[i] = (L[i] + R[i]) / 2;
    chans = [m];
  }
  return encodeWAV(chans, song.rate || M.RATE, M.loopFrame(song) || null);
}

export const songWav = (song) => wavOf(song, M.render(song));

async function sha256(bytes) {
  const d = new Uint8Array(await crypto.subtle.digest("SHA-256", bytes));
  return [...d].map((b) => b.toString(16).padStart(2, "0")).join("");
}

// what a WAV is made from: the song with its defaults filled in (so a song
// saved by an older Isai, opened in a newer one, is still the same song),
// less its title, its description and the note itself, keys in order
const canon = (v) => (Array.isArray(v) ? v.map(canon) : v && typeof v === "object"
  ? Object.fromEntries(Object.keys(v).sort().filter((k) => v[k] !== undefined).map((k) => [k, canon(v[k])])) : v);
const songText = (song) =>
  JSON.stringify(canon({ ...M.newSong(song.system), ...song, made: undefined, title: undefined, about: undefined }));
export const songDigest = (song) => sha256(new TextEncoder().encode(songText(song)));

export async function madeNote(song, wav) {
  return { engine: M.ENGINE, wav: await sha256(wav), song: await songDigest(song), current: true };
}

// before a song is saved: is it still what its WAV was made from?
export async function refreshNote(song) {
  if (song.made) song.made.current = (await songDigest(song)) === song.made.song;
  return song;
}

// why a song's WAV should be made again, or null
export function needsWav(song, wavExists) {
  if (!wavExists) return "it has no WAV";
  if (!song.made) return "its WAV was not made by Isai, or before Isai noted it";
  if (!song.made.current) return "it has changed since its WAV was made";
  if (song.made.engine !== M.ENGINE) return `its WAV was made by Isai engine ${song.made.engine}; this is ${M.ENGINE}`;
  return null;
}
