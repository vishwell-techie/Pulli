// The project: the game as `pulli pack` builds it, measured against the
// spec's limits (SPEC §2): the package's size and entries, each part
// against the memory a game holds at once, what is read as it starts, and
// the Pico 2 board's flash. The biggest parts are listed, to see what to
// make smaller.
import { h, status, api, shared, refreshBudget, help } from "./app.js";

export function project(root) {
  const out = h("div");
  const plan = h("div", { className: "box", style: "margin-bottom:14px" });
  const button = h("button", { className: "on", onclick: measure }, "Measure");
  root.append(plan,
    h("div", { className: "bar" }, button,
      help("Packs the game as pulli pack does, and checks it against the spec's limits: the package, what is held at once, " +
        "what is read as it starts, and the Pico 2 board's flash. A game with a lot of music takes a while.")),
    out);

  // ---- the budget: where the game goes, and what it may take ------------------
  const KINDS = ["code", "sprites", "maps", "sound effects", "music", "other"];
  function drawPlan() {
    const b = shared.budget;
    if (!b) return;
    const st = b.settings;
    const target = h("select", { id: "budget-target" }, ...Object.entries(b.targets).map(([k, name]) =>
      h("option", { value: k, selected: k === st.target }, name)));
    const strict = h("input", { type: "checkbox", id: "budget-strict", checked: st.strict });
    const limits = Object.fromEntries(KINDS.map((k) => [k, h("input", { type: "number", min: 0, step: 0.1, id: `budget-${k.replace(" ", "-")}`,
      value: st.limits[k] ?? "", placeholder: "none", style: "width:80px" })]));
    const mb = (n) => (n / 1048576).toFixed(2);
    plan.replaceChildren(
      h("div", { className: "bar", style: "margin-bottom:6px" }, h("h3", { style: "margin:0" }, "Budget"),
        help("Choose where the game is meant to go. The meter at the top shows what it takes against that, and Pattarai warns " +
          "when a save takes it past. Strict refuses those saves instead. Whatever the setting, Pattarai always refuses a " +
          "picture, map or sound the console could not use. The setting is kept in the game's folder (.pattarai.json), " +
          "which pack leaves out.")),
      h("div", { className: "bar" }, h("label", {}, "made for", target),
        h("label", { title: "Refuse saves that take the game past its budget or a limit" }, strict, "strict"),
        h("button", { onclick: () => save(target.value, strict.checked, limits) }, "Save setting")),
      h("table", { className: "limits" },
        h("tr", {}, h("th", {}, "kind"), h("th", { style: "text-align:right" }, "now"), h("th", {}, "limit (MB, empty for none)")),
        ...KINDS.map((k) => h("tr", {}, h("td", {}, k), h("td", { className: "num" }, `${mb(b.kinds[k])} MB`), h("td", {}, limits[k])))),
      b.error ? h("p", { className: "err", style: "margin:8px 0 0" }, "Not measured: " + b.error)
        : h("div", { style: "margin-top:10px" }, row(`the whole game, of ${b.target}`, b.size, b.room),
            ...KINDS.filter((k) => st.limits[k]).map((k) => row(`${k}, of its limit`, b.kinds[k], st.limits[k] * 1048576))),
      ...(b.over || []).map((o) => h("p", { className: "err", style: "margin:6px 0 0" }, "Over: " + o)));
  }
  async function save(target, strict, limits) {
    const set = { target, strict, limits: {} };
    for (const [k, input] of Object.entries(limits)) if (+input.value > 0) set.limits[k] = +input.value;
    try {
      await api.write(".pattarai.json", JSON.stringify(set, null, 1) + "\n");
      await refreshBudget();
      status(`Budget set: ${shared.budget.target}${strict ? ", strict" : ""}.`);
    } catch (e) { status("Not saved: " + e.message, true); }
  }
  shared.listeners.push((what) => { if (what === "budget") drawPlan(); });

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
    const over = bytes > of;
    return h("div", { className: "sizerow" }, h("span", { className: "name", title: name }, name),
      h("span", { className: "track" }, h("span", { style: `width:${Math.min(100, Math.max(1, bytes / of * 100))}%` +
        (over ? ";background:var(--bad)" : "") })),
      h("span", { className: over ? "err num" : "muted num" }, kb(bytes)));
  }
}
