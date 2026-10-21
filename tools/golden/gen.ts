// Goldens for bend/Text.bend and bend/Json.bend, from UniiChat's own code:
// `bun tools/golden/gen.ts UNIICHAT_DIR > cases.jsonl`. Each line is
// {"fn": name, "in": [args], "out": answer}; bend/tests/Golden.bend
// computes every one and compares.
const dir = process.argv[2];
process.env.UNII_DIR ??= "/tmp/mugen-golden-unii";
const { clip_pages, clip_page } = await import(dir + "/Clip.ts");
const { Memory } = await import(dir + "/Memory.ts");

const emoji = "🎉";
const big = (n: number, f: (k: number) => string) => Array.from({ length: n }, (_, k) => f(k)).join("");
const texts: string[] = [
  "", "a", "hello world", "héllo wörld", "日本語のテキスト", emoji, "a" + emoji + "b",
  "line one\nline two", "  lead\n  trail  ", "a \t\n\t b", "a\n\nb", "\n", " \n ", "a\r\nb",
  "x y", "x  \n　 y", "tab\tonly", "v\u000bt", "ctrl\u0001\u001f\u007f",
  "quote\" back\\ slash/", "nl\nend\n", "� at start", "ends with �",
  big(600, (k) => "é"), big(200, (k) => emoji), big(520, (k) => String.fromCharCode(97 + (k % 26))),
  big(29999, () => "a") + emoji, big(30000, () => "b") + "c", big(29990, () => "c") + "\n" + big(100, () => "d"),
  big(70000, (k) => (k % 997 === 0 ? "\n" : "x")), big(65000, (k) => (k % 3 === 0 ? emoji : "z")),
  big(30001, () => "e"), big(29999, () => "f") + "\n", big(15000, () => emoji) + "g",
];
const out: object[] = [];
for (const t of texts) {
  out.push({ fn: "flat", in: [t], out: Memory.flat(t) });
  out.push({ fn: "cut", in: [t], out: Memory.cut(t) });
  out.push({ fn: "bytes", in: [t], out: Memory.bytes(t) });
  out.push({ fn: "units", in: [t], out: t.length });
  out.push({ fn: "trim", in: [t], out: t.trim() });
  out.push({ fn: "pages", in: [t], out: clip_pages(t) });
  out.push({ fn: "stringify", in: [t], out: JSON.stringify(t) });
  for (const at of [0, 1, 29999, 30000, 45000]) {
    if (at <= t.length) {
      out.push({ fn: "page_at", in: [t, at], out: clip_page(t, at) });
    }
  }
}
const docs = [
  '{"a":1,"b":[true,false,null],"c":{"d":"e\\n\\u00e9\\ud83c\\udf89"},"e":-15}',
  '[]', '{}', '[[],{},[{}]]', ' { "x" : [ 1 , 2 ] } ', '"\\"\\\\\\/\\b\\f\\n\\r\\t"',
  '{"kind":"user","text":"hi","i":0,"size":8,"date":"2026-10-20T21:40:00.000Z"}',
  JSON.stringify({ deep: [[[[[[["x"]]]]]]], s: big(1000, (k) => String.fromCharCode(32 + (k % 90))) }),
];
for (const d of docs) {
  out.push({ fn: "reparse", in: [d], out: JSON.stringify(JSON.parse(d)) });
}
for (const o of out) {
  console.log(JSON.stringify(o));
}
