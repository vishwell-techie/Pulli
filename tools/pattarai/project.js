// The project: the game as `pulli pack` builds it, measured against the
// spec's limits (SPEC §2): the package's size and entries, each part
// against the memory a game holds at once, what is read as it starts, and
// the Pico 2 board's flash. The biggest parts are listed, to see what to
// make smaller.
import { h, status } from "./app.js";

export function project(root) {
  const out = h("div");
  const button = h("button", { className: "on", onclick: measure }, "Measure");
  root.append(
    h("div", { className: "bar" }, button,
      h("span", { className: "muted" }, "Packs the game as pulli pack does (a game with a lot of music takes a while).")),
    out);

  const kb = (n) => (n < 1048576 ? `${Math.ceil(n / 1024).toLocaleString("en")} KB` : `${(n / 1048576).toFixed(2)} MB`);

  async function measure() {
    button.disabled = true;
    status("Packing the game to measure it…");
    try {
      const r = await (await fetch("/api/project", { method: "POST", headers: { "X-Pulli-Token": location.hash.slice(1) } })).json();
      if (r.error) {
        out.replaceChildren(h("p", { className: "err" }, "The game does not pack: " + r.error));
        status("The game does not pack.", true);
        return;
      }
      const max = r.entries[0]?.[1] || 1;
      const kinds = {};
      for (const [n, b] of r.entries) {
        const k = n.endsWith(".lua") ? "code" : n.endsWith(".kolam") ? "sprites" : n.endsWith(".ooru") ? "maps"
          : n === "sfx.oli" ? "sound effects" : n === "music.isai" ? "music" : "other";
        kinds[k] = (kinds[k] || 0) + b;
      }
      out.replaceChildren(
        h("div", { className: "box", style: "margin-bottom:12px" }, h("h3", {}, `The package: ${kb(r.size)}`),
          ...r.checks.map(([ok, text], i) => h("div", { className: ok ? "" : i === 4 ? "warn" : "err", style: "margin:3px 0" },
            ok ? "✓ " : i === 4 ? "⚠ " : "✗ ", text)),
          ...r.notes.map((n) => h("div", { className: "muted", style: "margin:3px 0" }, "• " + n))),
        h("div", { className: "cols" },
          h("div", { className: "box" }, h("h3", {}, "By kind"),
            ...Object.entries(kinds).sort((a, b) => b[1] - a[1]).map(([k, b]) => row(k, b, r.size))),
          h("div", { className: "box wide" }, h("h3", {}, "Biggest entries"),
            ...r.entries.slice(0, 16).map(([n, b]) => row(n, b, max))),
          r.sounds.length ? h("div", { className: "box" }, h("h3", {}, "Each sound, as it is read"),
            ...[...r.sounds].sort((a, b) => b[1] - a[1]).slice(0, 12).map(([n, b]) => row(n, b, Math.max(...r.sounds.map((s) => s[1]))))) : ""));
      status(r.ok ? `The game packs to ${kb(r.size)}, within the spec's limits.` : "The game is past a limit of the spec.", !r.ok);
    } catch (e) { status(e.message, true); } finally { button.disabled = false; }
  }

  function row(name, bytes, of) {
    return h("div", { className: "sizerow" }, h("span", { className: "name" }, name),
      h("span", { className: "track" }, h("span", { style: `width:${Math.max(1, bytes / of * 100)}%` })),
      h("span", { className: "muted num" }, kb(bytes)));
  }
}
