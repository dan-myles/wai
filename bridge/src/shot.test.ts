import { expect, test } from "bun:test";
import { fakeScreenshot } from "./fake-shot";
import { CAPACITY, decode, parseTga } from "./shot";

test("decodes a painted message", () => {
  const payload = "what should I do next? ünï\0character: Bob\nzone: Goldshire";
  const shot = decode(parseTga(fakeScreenshot({ seq: 300, slot: 42, kind: 1, payload })));
  expect(shot).toEqual({ seq: 300, slot: 42, kind: 1, payload });
});

test("fills the full capacity", () => {
  const payload = "x".repeat(CAPACITY - 11);
  expect(decode(parseTga(fakeScreenshot({ seq: 65535, slot: 500, kind: 3, payload })))?.payload).toBe(payload);
});

test("ignores ordinary screenshots", () => {
  const img = parseTga(fakeScreenshot({ seq: 1, slot: 1, kind: 1, payload: "x" }).fill(30, 18));
  expect(decode(img)).toBeUndefined();
});
