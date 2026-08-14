-- Fairy attacking moves, taught by level-up.  HAND-AUTHORED, safe to edit.
--
-- data/moves_extra.lua adds the five Gen 6 Fairy attacks, but a move nothing
-- learns is a move that does not exist as far as a player is concerned.  BW2
-- learnsets predate the type, so there is nothing to generate from -- these
-- assignments are by hand.
--
-- Rules used:
--   * only species that are FAIRY in data/modern_types.lua, plus the four
--     vanilla ones the retype pass makes Fairy (Clefairy, Clefable,
--     Jigglypuff, Wigglytuff) and Mr. Mime
--   * FAIRY_WIND early on everything, so a freshly caught Fairy can attack
--     with its own type at once
--   * PLAY_ROUGH to the physical attackers (Granbull, Mawile, Azumarill,
--     Marill line), the special moves to the special ones
--   * MOONBLAST late and only to the final stages, so it stays a payoff
--   * levels sit inside each species' existing learnset band rather than at
--     the end of it
--
-- Applied to LIVE Data at game.ready, not through the registry: `learnset` is
-- a list, and a record patch replaces a list wholesale, so patching would mean
-- restating every one of these species' full learnsets.
return {
  -- baby and early Fairies
  CLEFFA         = { { 8, "FAIRY_WIND" } },
  IGGLYBUFF      = { { 8, "FAIRY_WIND" } },
  AZURILL        = { { 8, "FAIRY_WIND" } },
  TOGEPI         = { { 9, "FAIRY_WIND" }, { 21, "DRAINING_KISS" } },
  SNUBBULL       = { { 10, "FAIRY_WIND" }, { 28, "PLAY_ROUGH" } },
  MARILL         = { { 10, "FAIRY_WIND" }, { 30, "PLAY_ROUGH" } },
  RALTS          = { { 12, "FAIRY_WIND" } },
  COTTONEE       = { { 12, "FAIRY_WIND" } },
  MIME_JR        = { { 12, "FAIRY_WIND" } },
  -- middle stages
  KIRLIA         = { { 14, "FAIRY_WIND" }, { 32, "DRAINING_KISS" } },
  TOGETIC        = { { 16, "FAIRY_WIND" }, { 34, "DAZZLING_GLEAM" } },
  -- final stages
  AZUMARILL      = { { 18, "FAIRY_WIND" }, { 34, "PLAY_ROUGH" } },
  GRANBULL       = { { 18, "FAIRY_WIND" }, { 36, "PLAY_ROUGH" } },
  MAWILE         = { { 18, "FAIRY_WIND" }, { 36, "PLAY_ROUGH" } },
  WHIMSICOTT     = { { 20, "FAIRY_WIND" }, { 38, "DAZZLING_GLEAM" },
                     { 50, "MOONBLAST" } },
  GARDEVOIR      = { { 20, "FAIRY_WIND" }, { 38, "DAZZLING_GLEAM" },
                     { 52, "MOONBLAST" } },
  TOGEKISS       = { { 20, "DAZZLING_GLEAM" }, { 50, "MOONBLAST" } },
  -- the vanilla Fairies, made Fairy by the retype pass
  CLEFAIRY       = { { 14, "FAIRY_WIND" }, { 32, "DAZZLING_GLEAM" } },
  CLEFABLE       = { { 14, "FAIRY_WIND" }, { 34, "DAZZLING_GLEAM" },
                     { 50, "MOONBLAST" } },
  JIGGLYPUFF     = { { 14, "FAIRY_WIND" }, { 32, "DAZZLING_GLEAM" } },
  WIGGLYTUFF     = { { 14, "FAIRY_WIND" }, { 34, "DAZZLING_GLEAM" },
                     { 50, "MOONBLAST" } },
  MR_MIME        = { { 16, "FAIRY_WIND" }, { 36, "DAZZLING_GLEAM" } },
}
