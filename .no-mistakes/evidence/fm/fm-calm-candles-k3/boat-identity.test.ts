// Temporary validation check (not part of the repo): the default boat after the candles
// change paints the exact same Raster cells as the base commit's boat.
import { describe, expect, test } from "claude-code/testing";
import { createCalmWorkingShipSprite as baseSprite } from "../lib/base/fm-calm-working-ship-sprite.ts";
import { CALM_SHIP_RASTER_PALETTES as BASE_PALETTES, packCalmShipRasterCells as basePack } from "../lib/base/fm-calm-ship-raster.ts";
import { CALM_WORKING_SCENE_DEFAULT, createCalmWorkingSceneSprite, parseCalmWorkingScene } from "../lib/fm-calm-working-ship-sprite.ts";
import { CALM_SHIP_RASTER_PALETTES, packCalmShipRasterCells } from "../lib/fm-calm-ship-raster.ts";

describe("boat identity against base 43bf6d3", () => {
  test("the default scene is the boat for every non-candles value", () => {
    expect(CALM_WORKING_SCENE_DEFAULT).toBe("boat");
    for (const v of [undefined, "", "boat", "Candles", "CANDLES", "candle", "fish", "candles candles", "candles.", "c andles"]) {
      expect(parseCalmWorkingScene(v)).toBe("boat");
    }
    for (const v of ["candles", "candles\n", "  candles \n\n", "\tcandles\r\n", "\u00a0candles"]) expect(parseCalmWorkingScene(v)).toBe("candles");
  });
  for (const family of ["dark", "light"] as const) {
    for (let from = 0; from <= 200; from += 4) {
      test(`${family}: frames and packed raster cells match the base boat at widths ${from}..${Math.min(200, from + 3)} over 400 steps with freezes and hidden resizes`, () => {
        for (let width = from; width <= Math.min(200, from + 3); width += 1) {
          const a = baseSprite();
          const b = createCalmWorkingSceneSprite(parseCalmWorkingScene(undefined));
          for (let step = 0; step < 400; step += 1) {
            if (step % 97 === 50) { for (let k = 0; k < 7; k += 1) { a.tick(); b.tick(); } a.restoreLastRendered(); b.restoreLastRendered(); }
            if (step % 131 === 70) { const w2 = Math.max(1, (width * 3) % 157); a.clampToWidth(w2); b.clampToWidth(w2); }
            const fa = a.frame(width), fb = b.frame(width);
            if (JSON.stringify(fb) !== JSON.stringify(fa)) throw new Error(`frame differs at width ${width} step ${step}`);
            if (width > 0 && packCalmShipRasterCells(fb, width, CALM_SHIP_RASTER_PALETTES[family]).cells !== basePack(fa, width, BASE_PALETTES[family]).cells) throw new Error(`raster differs at width ${width} step ${step}`);
            if (b.position() !== a.position() || b.direction() !== a.direction() || b.waterPhase() !== a.waterPhase()) throw new Error(`state differs at width ${width} step ${step}`);
            a.tick(); b.tick();
          }
        }
      });
    }
  }
});
