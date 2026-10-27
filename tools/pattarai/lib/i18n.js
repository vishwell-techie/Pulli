// Pattarai in Tamil: the editors' own words (tabs, buttons, headings,
// labels). Names that are code, files or notes (spr, sfx(3), S R G) stay as
// they are, as in the Tamil guide. Messages in the status line are English
// for now.

export const TA = {
  "code": "நிரல்", "sprites": "உருவங்கள்", "maps": "வரைபடங்கள்", "sounds": "ஒலிகள்", "music": "இசை",
  "Project": "திட்டம்", "▶ Run game": "▶ விளையாடு", "restart on save": "சேமித்ததும் மீண்டும் தொடங்கு",
  "Open": "திற", "New…": "புதிது…", "Save": "சேமி", "Save as…": "வேறு பெயரில் சேமி…", "✓ Check": "✓ சரிபார்",
  "✎ Pen": "✎ பேனா", "◧ Fill": "◧ நிரப்பு", "╱ Line": "╱ கோடு", "▭ Box": "▭ பெட்டி", "⊙ Pick": "⊙ எடு",
  "⌫ Erase": "⌫ அழி", "✥ Move": "✥ நகர்த்து", "Copy": "நகலெடு", "Paste": "ஒட்டு", "Clear": "துடை",
  "✎ Paint": "✎ வரை", "⧉ Copy": "⧉ நகலெடு", "Layer 0": "அடுக்கு 0", "Layer 1": "அடுக்கு 1",
  "show 0": "காட்டு 0", "show 1": "காட்டு 1", "show flags": "கொடிகளைக் காட்டு", "⇋ Flip": "⇋ புரட்டு",
  "⇵ Flip": "⇵ புரட்டு", "zoom": "பெரிதாக்கம்", "▶ Play": "▶ இயக்கு", "■ Stop": "■ நிறுத்து",
  "New Carnatic": "புதிய கர்நாடக இசை", "New western": "புதிய மேற்கத்திய இசை", "New chiptune": "புதிய சிப்ட்யூன்",
  "Make WAV": "WAV உருவாக்கு", "+ Part": "+ பகுதி", "Measure": "அளவிடு", "More like this": "இதைப் போல் இன்னொன்று",
  "Start from:": "தொடக்கம்:", "play on change": "மாற்றியதும் ஒலிக்கவிடு", "Trim to choice": "தேர்ந்ததை மட்டும் வை",
  "Fade in": "மெல்லத் தொடங்கு", "Fade out": "மெல்ல முடி", "Normalise": "ஒலியளவைச் சீராக்கு", "Quieter": "மெதுவாக்கு",
  "Reverse": "தலைகீழாக்கு", "Make mono": "ஒற்றை அலைவரிசையாக்கு", "Replace": "மாற்று", "Replace all": "அனைத்தையும் மாற்று",
  "Sprites": "உருவங்கள்", "Sounds": "ஒலிகள்", "Music": "இசை", "Maps": "வரைபடங்கள்",
  "Colours": "வண்ணங்கள்", "Sheet": "தாள்", "Animation": "அசைவூட்டம்", "Map": "வரைபடம்", "Tiles": "டைல்கள்",
  "Settings": "அமைப்புகள்", "Edit a WAV": "WAV-ஐத் திருத்து", "Under the cursor": "சுட்டியின் கீழ்",
  "Put in the code": "நிரலில் சேர்", "Roll: the part in hand": "சுருள்: கையிலுள்ள பகுதி", "By kind": "வகைவாரியாக",
  "Biggest entries": "பெரிய பதிவுகள்", "Each sound, as it is read": "ஒவ்வோர் ஒலியும், படிக்கப்படும்போது",
  "raga": "ராகம்", "tala": "தாளம்", "scale": "சுரவரிசை", "time": "தாளம்", "tempo": "வேகம்", "drone": "சுருதி",
  "drums": "தாளவாத்தியம்", "cycles": "ஆவர்த்தனங்கள்", "steps a beat": "ஒரு துடிப்பில் படிகள்", "swing": "ஊசல்",
  "octave": "ஸ்தாயி", "volume": "ஒலியளவு", "pan": "இடம்–வலம்", "key": "சுருதி", "mono": "ஒற்றை அலைவரிசை",
  "Arohanam": "ஆரோகணம்", "Avarohanam": "அவரோகணம்", "Up": "ஏற்றம்", "Down": "இறக்கம்",
  "arpeggio speed": "ஆர்பெஜியோ வேகம்", "loops from cycle": "மீண்டும் தொடங்கும் ஆவர்த்தனம்",
  "frames": "சட்டகங்கள்", "a second": "வினாடிக்கு", "wave": "அலை", "onion skin": "முந்தையதை மங்கலாகக் காட்டு",
  "Sprite ": "உருவம் ",
  "backdrops": "பின்னணிகள்", "Backdrops": "பின்னணிகள்", "Backdrop ": "பின்னணி ", "Import picture…": "படத்தைக் கொண்டுவா…",
  "■ Filled box": "■ நிரம்பிய பெட்டி", "▤ Gradient": "▤ வண்ணச்சரிவு", "dither": "புள்ளிக் கலப்பு",
  "Map over it": "மேலே வரைபடம்", "capitals long": "பெரிய எழுத்து இரு அட்சரம்", "note names": "சுரப் பெயர்கள்", "drum pattern": "தாள அமைப்பு", "+ Drum part": "+ தாளப் பகுதி",
};

let lang = "en";
export const language = () => lang;

function walk(node) {
  if (node.nodeType === 3) {
    const raw = node.nodeValue, key = raw.trim();
    if (key && TA[key]) node.nodeValue = raw.replace(key, TA[key]);
    else if (TA[raw]) node.nodeValue = TA[raw];
    return;
  }
  if (node.nodeType !== 1 || node.tagName === "TEXTAREA" || node.tagName === "SELECT" ||
      node.closest?.(".code-out, .hint, .complete, .problems, .keys")) return;     // code and notes stay as written
  for (const c of node.childNodes) walk(c);
}

// Put the page in Tamil, and keep what the editors draw later in Tamil too.
export function useTamil(root) {
  lang = "ta";
  document.documentElement.lang = "ta";
  walk(root);
  new MutationObserver((list) => {
    for (const m of list) {
      if (m.type === "characterData") walk(m.target);
      else for (const n of m.addedNodes) walk(n);
    }
  }).observe(root, { childList: true, subtree: true, characterData: true });
}
