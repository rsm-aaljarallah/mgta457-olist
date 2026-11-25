// Builds the Olist team presentation: deliverables/olist_presentation.pptx
// Run from the repo root:
//   NODE_PATH=<folder with pptxgenjs> OLIST_THEME_SCRIPT=<theme helper> node tools/deck/build_deck.js
// NODE_PATH must point at a folder where pptxgenjs is installed (npm install pptxgenjs).
// The colour theme is applied by a helper outside this repository; set OLIST_THEME_SCRIPT
// to its path, or leave it missing and the deck is written without the theme step.
// Speaker notes come from tools/deck/script.json, the same text as docs/presentation_outline.md.
// Screenshots come from docs/img (taken from the published dashboards on 2026-11-24).
// AI use: drafted with Claude (Anthropic), 2026-11-24, from the Chord project's deck script
// (see docs/ai_usage.md).
const fs = require("fs");
const path = require("path");
const pptxgen = require("pptxgenjs");
const THEME_SCRIPT = process.env.OLIST_THEME_SCRIPT || "";
let applyTheme = null;
try {
  if (!THEME_SCRIPT) throw new Error("OLIST_THEME_SCRIPT is not set");
  ({ applyTheme } = require(THEME_SCRIPT));
} catch (e) {
  console.warn("Theme helper not found, so the deck is written without the theme step:", THEME_SCRIPT);
}

const ROOT = path.resolve(__dirname, "..", "..");
const SCRIPT = require("./script.json");
const IMG = path.join(ROOT, "docs", "img");
const OUT = process.env.OLIST_DECK_OUT || path.join(ROOT, "deliverables", "olist_presentation.pptx");
const say = (n) => { const s = SCRIPT.find((x) => x.slide === n); return `${s.speaker} (${s.minutes} min): ${s.say}`; };

const THEME = {
  name: "Olist",
  headFontFace: "Cambria",
  bodyFontFace: "Calibri",
  colors: {
    dk1: "0B1F2A", lt1: "FFFFFF", dk2: "12384A", lt2: "EEF4F6",
    accent1: "0B84A5", accent2: "FFAB00", accent3: "5B7C8A", accent4: "C8DDE5",
    accent5: "0E5E78", accent6: "D9534F", hlink: "0B84A5", folHlink: "5B7C8A",
  },
};

const pres = new pptxgen();
pres.layout = "LAYOUT_WIDE"; // 13.33 x 7.5 in
pres.theme = { headFontFace: THEME.headFontFace, bodyFontFace: THEME.bodyFontFace };
pres.author = "AJ, Ruby, Merna";
pres.title = "Where Olist breaks its delivery promise, and what to fix first";
const C = pres.SchemeColor;

// ---------------------------------------------------------------- layouts
pres.defineSlideMaster({
  title: "DARK",
  background: { color: C.text1 },
  objects: [
    { placeholder: { options: { name: "title", type: "title", x: 0.8, y: 2.0, w: 11.7, h: 2.1, fontSize: 42, bold: true, color: C.background1, align: "left", valign: "top", margin: 0 }, text: "" } },
    { placeholder: { options: { name: "body", type: "body", x: 0.8, y: 4.4, w: 11.7, h: 1.8, fontSize: 20, color: C.accent4, align: "left", valign: "top", margin: 0 }, text: "" } },
  ],
});
pres.defineSlideMaster({
  title: "CONTENT",
  background: { color: C.background1 },
  margin: [0.5, 0.6, 0.7, 0.6],
  objects: [
    { placeholder: { options: { name: "title", type: "title", x: 0.6, y: 0.35, w: 12.1, h: 0.9, fontSize: 30, bold: true, color: C.text1, align: "left", valign: "middle", margin: 0 }, text: "" } },
    { text: { text: "MGTA 457  |  Olist delivery promise", options: { x: 0.6, y: 7.0, w: 8, h: 0.3, fontSize: 10, color: C.accent3, margin: 0 } } },
  ],
  slideNumber: { x: 12.2, y: 7.0, w: 0.6, h: 0.3, fontSize: 10, color: C.accent3, align: "right" },
});

// ---------------------------------------------------------------- helpers
function pngSize(file) {
  const b = fs.readFileSync(path.join(IMG, file));
  return { w: b.readUInt32BE(16), h: b.readUInt32BE(20) };
}
function shot(slide, file, x, y, maxW, maxH, name) {
  // Fit the screenshot inside maxW x maxH without stretching it.
  const { w, h } = pngSize(file);
  let ww = maxW, hh = maxW * h / w;
  if (hh > maxH) { hh = maxH; ww = maxH * w / h; }
  slide.addImage({ path: path.join(IMG, file), x, y, w: ww, h: hh, objectName: name, altText: name,
    shadow: { type: "outer", color: "0B1F2A", opacity: 0.25, blur: 8, offset: 3, angle: 90 } });
  return { w: ww, h: hh };
}
function stat(slide, x, y, w, big, label, name, color) {
  slide.addShape(pres.ShapeType.roundRect, { x, y, w, h: 1.55, rectRadius: 0.08, fill: { color: C.background2 }, line: { color: C.background2 }, objectName: name + " card" });
  slide.addText(big, { x: x + 0.2, y: y + 0.12, w: w - 0.4, h: 0.8, fontSize: 34, bold: true, color: color || C.accent1, fontFace: THEME.headFontFace, margin: 0, isTextBox: true, objectName: name + " value" });
  slide.addText(label, { x: x + 0.2, y: y + 0.92, w: w - 0.4, h: 0.55, fontSize: 13, color: C.text2, margin: 0, valign: "top", isTextBox: true, objectName: name + " label" });
}
function points(slide, items, x, y, w, h, size) {
  slide.addText(items.map((t, i) => ({ text: t, options: { bullet: true, breakLine: i < items.length - 1, paraSpaceAfter: 10 } })),
    { x, y, w, h, fontSize: size || 16, color: C.text1, valign: "top", margin: 0, isTextBox: true, objectName: "Key points" });
}
function content(n, section) {
  const s = pres.addSlide({ masterName: "CONTENT", sectionTitle: section });
  s.addText(SCRIPT.find((x) => x.slide === n).title, { placeholder: "title" });
  s.addNotes(say(n));
  return s;
}

// ---------------------------------------------------------------- 1 title
pres.addSection({ title: "The question" });
let s = pres.addSlide({ masterName: "DARK", sectionTitle: "The question" });
s.addText(SCRIPT[0].title, { placeholder: "title" });
s.addText("MGTA 457 Business Intelligence Systems, Fall 2026\nAJ, Ruby, Merna", { placeholder: "body" });
s.addNotes(say(1));

// ---------------------------------------------------------------- 2 data
s = content(2, "The question");
stat(s, 0.6, 1.5, 2.85, "99,441", "Olist marketplace orders, Sep 2016 to Oct 2018", "Orders");
stat(s, 3.68, 1.5, 2.85, "8,000", "sellers who asked to join (marketing funnel)", "Leads");
stat(s, 6.76, 1.5, 2.85, "27", "states with their 2018 population (IBGE)", "States");
stat(s, 9.84, 1.5, 2.85, "8.6%", "of 95,901 judged orders broke their promise", "Broken rate", "D9534F");
s.addText("What we ask", { x: 0.6, y: 3.45, w: 6, h: 0.45, fontSize: 22, bold: true, color: C.text1, fontFace: THEME.headFontFace, margin: 0, isTextBox: true, objectName: "Question heading" });
points(s, [
  "What does a broken promise cost in reviews?  (Head of Customer Experience)",
  "Which routes break it, and what kind of fix does each need?  (Head of Logistics)",
  "Where would sellers close to the customer help?  (Head of Seller Acquisition)",
], 0.6, 4.0, 12.1, 2.0, 18);
s.addText("A promise is broken when the order was not delivered by the end of the promised day. We count days, not timestamps.",
  { x: 0.6, y: 6.1, w: 12.1, h: 0.6, fontSize: 15, italic: true, color: C.text2, margin: 0, isTextBox: true, objectName: "Definition" });

// ---------------------------------------------------------------- 3 pipeline
pres.addSection({ title: "How we built it" });
s = content(3, "How we built it");
shot(s, "lineage.png", 0.6, 1.4, 12.1, 4.6, "Lineage map");
s.addText("31 cleaning rules  ·  2 facts, 4 dimensions  ·  1 metric view for the filtered rates  ·  24 checks  ·  the dashboards calculate nothing",
  { x: 0.6, y: 6.25, w: 12.1, h: 0.5, fontSize: 15, color: C.accent5, bold: true, margin: 0, align: "center", isTextBox: true, objectName: "Pipeline summary" });

// ---------------------------------------------------------------- 4 traps
s = content(4, "How we built it");
[
  ["Late by timestamp", "1,292", "on-time deliveries look late, because the promise has no time of day. We compare days."],
  ["Joins on the wrong grain", "+4.6%", "item value when items join payments; 99k customers become 15M rows via locations. We aggregate first."],
  ["Repeated reviews", "547", "orders with 2+ reviews, 202 with different scores. We keep the latest: one score per order."],
  ["A window that ends early", "56", "deliveries in Sep 2018 after 8,314 in Aug. We judge only promises due by Aug 31, 2018."],
].forEach(([head, big, text], i) => {
  const x = 0.6 + (i % 2) * 6.2, y = 1.5 + Math.floor(i / 2) * 2.65;
  s.addShape(pres.ShapeType.roundRect, { x, y, w: 5.9, h: 2.4, rectRadius: 0.08, fill: { color: C.background2 }, line: { color: C.background2 }, objectName: head + " card" });
  s.addText(head, { x: x + 0.3, y: y + 0.2, w: 5.3, h: 0.45, fontSize: 19, bold: true, color: C.text1, fontFace: THEME.headFontFace, margin: 0, isTextBox: true, objectName: head + " heading" });
  s.addText(big, { x: x + 0.3, y: y + 0.75, w: 1.8, h: 0.8, fontSize: 32, bold: true, color: C.accent1, fontFace: THEME.headFontFace, margin: 0, isTextBox: true, objectName: head + " value" });
  s.addText(text, { x: x + 2.15, y: y + 0.75, w: 3.5, h: 1.45, fontSize: 14, color: C.text2, margin: 0, valign: "top", isTextBox: true, objectName: head + " text" });
});

// ---------------------------------------------------------------- 5 dashboard 1
pres.addSection({ title: "What we found" });
s = content(5, "What we found");
shot(s, "dash_1_cost.png", 0.6, 1.35, 8.2, 5.5, "Dashboard 1 screenshot");
points(s, [
  "8.6% of judged orders, but 36.7% of in-window orders with a 1-2 star review, canceled ones included",
  "The score holds while parcels arrive early, then drops right after the promised day: 4.03 on the day, 2.10 at 4-7 days late",
  "In the same delivery week, late orders score 0.4 to 1.8 stars lower",
  "70.1% of late parcels with a review were reviewed before arrival: 1.65 stars, against 3.72 after",
], 9.1, 1.5, 3.7, 5.2, 15);

// ---------------------------------------------------------------- 6 routes
s = content(6, "What we found");
shot(s, "dash_2_routes.png", 0.6, 1.35, 8.2, 5.5, "Dashboard 2 routes screenshot");
stat(s, 9.1, 1.5, 3.6, "678", "excess broken promises, Sao Paulo to Rio (17.1% +/- 0.8)", "SP to RJ", "D9534F");
stat(s, 9.1, 3.25, 3.6, "637", "the next nine routes together", "Next nine");
points(s, ["5 of the top 10 routes go into the Northeast", "Excess = broken minus what the 8.7% national rate on single-seller orders predicts"], 9.1, 5.05, 3.6, 1.7, 14);

// ---------------------------------------------------------------- 7 two kinds of fix
s = content(7, "What we found");
shot(s, "dash_2_charts.png", 0.6, 1.35, 8.2, 5.5, "Dashboard 2 charts screenshot");
points(s, [
  "Busy months (Nov 2017, Feb and Mar 2018): 22.1% of orders, 42.9% of broken promises → busy-season plan",
  "The Northeast breaks promises in ordinary months too → lasting fix",
  "A promise 3 days later: 8.6% → only 6.6%",
  "72.2% of late parcels from one seller reached the carrier on time: most of the delay is after the handover",
], 9.1, 1.5, 3.7, 5.2, 15);

// ---------------------------------------------------------------- 8 local sellers
s = content(8, "What we found");
shot(s, "dash_3_local_rio.png", 0.6, 1.35, 8.2, 5.5, "Dashboard 3 screenshot, Rio de Janeiro");
points(s, [
  "Orders per 100,000 residents: Rio 56.4, Sao Paulo 71.7",
  "Active sellers per million: Rio 8.5, Sao Paulo 35.2",
  "91.5% of Rio's single-seller orders come from another state",
  "Rio customers, local sellers: 7.7% broken, 5 days. Sao Paulo sellers: 17.1%, 13 days. The gap is mostly in busy months; otherwise 8.7% vs 10.0%",
  "Rio got only 6.8% of the funnel recruits who sold",
], 9.1, 1.5, 3.7, 5.2, 15);

// ---------------------------------------------------------------- 9 trust
pres.addSection({ title: "Can we trust it" });
s = content(9, "Can we trust it");
shot(s, "dash_2_trust_checks.png", 0.6, 1.35, 7.6, 5.4, "Pipeline checks screenshot");
stat(s, 8.6, 1.5, 4.1, "24 / 24", "pipeline checks pass", "Checks", "00A972");
stat(s, 8.6, 3.2, 4.1, "3 rows", "of 415,201 order, item, payment and review rows set aside (0.001%)", "Quarantine");
stat(s, 8.6, 4.9, 4.1, "56 / 56", "design-document results recomputed from Gold match", "Doc numbers", "00A972");

// ---------------------------------------------------------------- 10 recommendations
pres.addSection({ title: "What to do" });
s = content(10, "What to do");
[
  ["Customer Experience", "Test a delay notice", "Send a new date before the review survey to customers whose parcel will miss. Measure the score against a control group."],
  ["Logistics", "Fix Sao Paulo to Rio first", "Review its carrier and transit days, and book extra capacity before busy months. Then the Northeast routes with a lasting-fix label."],
  ["Seller Acquisition", "Pilot recruiting in Rio", "Recruit Rio sellers in the top categories, and check that they deliver faster for the same products before counting on better reviews."],
].forEach(([who, what, text], i) => {
  const x = 0.6 + i * 4.1;
  s.addShape(pres.ShapeType.roundRect, { x, y: 1.5, w: 3.85, h: 3.6, rectRadius: 0.08, fill: { color: C.background2 }, line: { color: C.background2 }, objectName: who + " card" });
  s.addText(who, { x: x + 0.3, y: 1.7, w: 3.3, h: 0.4, fontSize: 14, bold: true, color: C.accent3, margin: 0, isTextBox: true, objectName: who + " reader" });
  s.addText(what, { x: x + 0.3, y: 2.15, w: 3.3, h: 0.9, fontSize: 22, bold: true, color: C.text1, fontFace: THEME.headFontFace, margin: 0, valign: "top", isTextBox: true, objectName: who + " action" });
  s.addText(text, { x: x + 0.3, y: 3.15, w: 3.3, h: 1.8, fontSize: 15, color: C.text2, margin: 0, valign: "top", isTextBox: true, objectName: who + " detail" });
});
s.addText("How we will know: the score of late orders (Dashboard 1), the rate on each fixed route (Dashboard 2), and the local share of Rio's orders (Dashboard 3). The same pipeline reruns on new months.",
  { x: 0.6, y: 5.45, w: 12.1, h: 0.9, fontSize: 16, italic: true, color: C.text2, margin: 0, valign: "top", isTextBox: true, objectName: "How we will know" });

// ---------------------------------------------------------------- 11 limits and close
s = pres.addSlide({ masterName: "DARK", sectionTitle: "What to do" });
s.addText(SCRIPT[10].title, { placeholder: "title" });
s.addText("Promise and review links are correlations  ·  no carrier or tracking data  ·  busy months found in the same data  ·  deliveries recorded only to August 2018\n\nQuestions?", { placeholder: "body" });
s.addNotes(say(11));

pres.writeFile({ fileName: OUT }).then(() => (applyTheme ? applyTheme(OUT, THEME) : null)).then(() => console.log("wrote", OUT));
