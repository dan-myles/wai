// Minimal Lua literal reader/writer: enough for WoW SavedVariables and Data.lua.

export type LuaValue = string | number | boolean | null | LuaValue[] | { [key: string]: LuaValue };

const IDENT = /[A-Za-z_]\w*/y;
const FIELD_NAME = /([A-Za-z_]\w*)\s*=(?!=)/y;
const NUMBER = /-?(?:\d+\.?\d*|\.\d+)(?:[eE][+-]?\d+)?/y;
const ESCAPES: Record<string, string> = {
  n: "\n", t: "\t", r: "\r", a: "\x07", b: "\b", f: "\f", v: "\v",
  "\\": "\\", '"': '"', "'": "'", "\n": "\n",
};

class Parser {
  i = 0;
  constructor(private s: string) {}

  fail(msg: string): never {
    throw new Error(`lua parse: ${msg} at offset ${this.i}`);
  }

  skip() {
    for (;;) {
      const c = this.s[this.i];
      if (c === " " || c === "\t" || c === "\n" || c === "\r") this.i++;
      else if (c === "-" && this.s[this.i + 1] === "-") {
        const nl = this.s.indexOf("\n", this.i);
        this.i = nl < 0 ? this.s.length : nl + 1;
      } else return;
    }
  }

  eof() {
    this.skip();
    return this.i >= this.s.length;
  }

  eat(ch: string) {
    this.skip();
    if (this.s[this.i] !== ch) this.fail(`expected '${ch}'`);
    this.i++;
  }

  match(re: RegExp) {
    re.lastIndex = this.i;
    const m = re.exec(this.s);
    if (m) this.i += m[0].length;
    return m;
  }

  ident() {
    this.skip();
    return this.match(IDENT)?.[0] ?? this.fail("expected identifier");
  }

  value(): LuaValue {
    this.skip();
    const c = this.s[this.i];
    if (c === "{") return this.table();
    if (c === '"' || c === "'") return this.string();
    const num = this.match(NUMBER);
    if (num) return Number(num[0]);
    const id = this.ident();
    if (id === "true") return true;
    if (id === "false") return false;
    if (id === "nil") return null;
    this.fail(`unexpected '${id}'`);
  }

  string(): string {
    const quote = this.s[this.i++];
    let out = "";
    for (;;) {
      const c = this.s[this.i++];
      if (c === undefined) this.fail("unterminated string");
      if (c === quote) return out;
      if (c !== "\\") {
        out += c;
        continue;
      }
      const e = this.s[this.i++]!;
      if (e in ESCAPES) out += ESCAPES[e];
      else if (/\d/.test(e)) {
        let digits = e;
        while (digits.length < 3 && /\d/.test(this.s[this.i] ?? "")) digits += this.s[this.i++];
        out += String.fromCharCode(Number(digits));
      } else this.fail(`bad escape \\${e}`);
    }
  }

  table(): LuaValue {
    this.eat("{");
    const entries: [string | number, LuaValue][] = [];
    let n = 0;
    for (;;) {
      this.skip();
      if (this.s[this.i] === "}") {
        this.i++;
        break;
      }
      let key: string | number;
      if (this.s[this.i] === "[") {
        this.i++;
        const k = this.value();
        if (typeof k !== "string" && typeof k !== "number") this.fail("unsupported key");
        key = k;
        this.eat("]");
        this.eat("=");
      } else {
        key = this.match(FIELD_NAME)?.[1] ?? ++n;
      }
      entries.push([key, this.value()]);
      this.skip();
      const sep = this.s[this.i];
      if (sep === "," || sep === ";") this.i++;
      else if (sep !== "}") this.fail("expected ',' or '}'");
    }
    // Tables keyed exactly 1..n become arrays; everything else becomes an object.
    const sorted = entries.every(([k]) => typeof k === "number")
      ? [...entries].sort((a, b) => (a[0] as number) - (b[0] as number))
      : undefined;
    if (sorted?.every(([k], idx) => k === idx + 1)) return sorted.map(([, v]) => v);
    return Object.fromEntries(entries.map(([k, v]) => [String(k), v]));
  }
}

/** Parses a SavedVariables file: a sequence of `Name = <literal>` assignments. */
export function parseSavedVariables(src: string): Record<string, LuaValue> {
  const p = new Parser(src);
  const out: Record<string, LuaValue> = {};
  while (!p.eof()) {
    const name = p.ident();
    p.eat("=");
    out[name] = p.value();
  }
  return out;
}

function quote(s: string) {
  return `"${s.replace(/[\\"\x00-\x1f\x7f]/g, (c) =>
    c === "\\" ? "\\\\" : c === '"' ? '\\"' : c === "\n" ? "\\n" : `\\${String(c.charCodeAt(0)).padStart(3, "0")}`,
  )}"`;
}

export function toLua(v: unknown, indent = ""): string {
  if (v === null || v === undefined) return "nil";
  if (typeof v === "boolean") return String(v);
  if (typeof v === "number") return Number.isFinite(v) ? String(v) : "0";
  if (typeof v === "string") return quote(v);
  const next = indent + "  ";
  const fields = Array.isArray(v)
    ? v.map((x) => toLua(x, next))
    : Object.entries(v as object)
        .filter(([, x]) => x !== undefined)
        .map(([k, x]) => `[${quote(k)}] = ${toLua(x, next)}`);
  if (!fields.length) return "{}";
  return `{\n${fields.map((f) => `${next}${f},\n`).join("")}${indent}}`;
}
