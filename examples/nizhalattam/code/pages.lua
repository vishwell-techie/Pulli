-- pages.lua — the pages of the Puppet King's story, one hidden in each
-- story: the story told in pieces (no ending depends on them). Read when a
-- page is found, or read again at the Aasaan's box, and let go after.
--
--   pages.COUNT        how many there are
--   pages.text(n)      the nth page found, in the language chosen: they are
--                      read in order, whichever story each was found in

local lines = require("lines")

local TEXT = {
  en = {
    "Fifty years ago a carver made one puppet before all the others: a king, to be the hero.",
    "He was painted in gold and sky blue, and every night the children cheered him.",
    "Then the troupe needed someone to lose. The carver's student took up a brush.",
    "Over the gold went black, over the smile a scowl. The hero became the Puppet King.",
    "Every night since, for fifty years, he has lost, so that others could be cheered.",
    "The student who repainted him taught a boy the craft. The boy is the Puppet Master.",
  },
  ta = {
    "ஐம்பது ஆண்டுகளுக்கு முன், ஒரு சிற்பி மற்ற எல்லாப் பாவைகளுக்கும் முன் ஒன்றைச் செதுக்கினார்: நாயகனாக ஒரு அரசன்.",
    "அவனுக்குத் தங்கமும் வான் நீலமும் பூசப்பட்டன; ஒவ்வொரு இரவும் குழந்தைகள் அவனுக்கு ஆரவாரம் செய்தனர்.",
    "பிறகு குழுவுக்குத் தோற்க ஒருவன் தேவைப்பட்டான். சிற்பியின் மாணவர் தூரிகையை எடுத்தார்.",
    "தங்கத்தின் மேல் கருமை, புன்னகையின் மேல் சுழிப்பு. நாயகன் பாவை அரசன் ஆனான்.",
    "அன்று முதல் ஐம்பது ஆண்டுகள், ஒவ்வொரு இரவும், மற்றவர்கள் ஆரவாரம் பெற அவன் தோற்றான்.",
    "அவனுக்கு மறுவண்ணம் பூசிய மாணவர் ஒரு சிறுவனுக்கு இக்கலையைக் கற்பித்தார். அந்தச் சிறுவனே ஆசான்.",
  },
}

local pages = { COUNT = #TEXT.en }

function pages.text(n) return TEXT[lines.lang][n] end

return pages
