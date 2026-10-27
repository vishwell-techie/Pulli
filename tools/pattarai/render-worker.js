// Renders a song off the page's thread, so the editor stays awake.
import { render } from "./lib/music.js";

onmessage = (e) => {
  try {
    const channels = render(e.data);
    postMessage({ channels }, channels.map((c) => c.buffer));
  } catch (err) {
    postMessage({ error: err.message });
  }
};
