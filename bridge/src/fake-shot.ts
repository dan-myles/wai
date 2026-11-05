import { COLS, ROWS } from "./shot";

// Mirrors encode() + shootNext() in wai.lua, rendered into an uncompressed bottom-origin TGA.
export function fakeScreenshot(opts: { seq: number; slot: number; kind: number; payload: string }) {
  const body = Buffer.from(opts.payload, "utf8");
  const bytes = [87, 65, 73, 2, opts.seq >> 8, opts.seq & 255, opts.slot >> 8, opts.slot & 255, opts.kind, body.length >> 8, body.length & 255, ...body];
  const bit = (k: number) => ((bytes[k >> 3] ?? 0) >> (7 - (k & 7))) & 1;
  const [width, height, block, left, top, margin] = [1280, 720, 3, 40, 40, 2];
  const px = Buffer.alloc(width * height * 3, 30);
  const set = (x: number, y: number, [r, g, b]: number[]) => {
    const i = ((height - 1 - y) * width + x) * 3;
    px[i] = b!;
    px[i + 1] = g!;
    px[i + 2] = r!;
  };
  // Stray magenta that must not confuse the frame search.
  for (let x = 0; x < 50; x++) set(x, 5, [255, 0, 255]);
  for (let y = 0; y < (ROWS + 2 * margin) * block; y++) {
    for (let x = 0; x < (COLS + 2 * margin) * block; x++) {
      const c = Math.floor(x / block) - margin;
      const r = Math.floor(y / block) - margin;
      let color = [255, 0, 255];
      if (c >= 0 && c < COLS && r >= 0 && r < ROWS) {
        const i = r * COLS + c;
        color = [bit(i * 3) * 255, bit(i * 3 + 1) * 255, bit(i * 3 + 2) * 255];
      }
      set(left + x, top + y, color);
    }
  }
  const header = Buffer.alloc(18);
  header[2] = 2;
  header.writeUInt16LE(width, 12);
  header.writeUInt16LE(height, 14);
  header[16] = 24;
  return Buffer.concat([header, px]);
}
