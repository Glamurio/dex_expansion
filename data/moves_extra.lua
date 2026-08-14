-- Written once by hand -- safe to edit.
--
-- Attacking FAIRY moves.
--
-- data/moves.lua is built from Black 2/White 2 learnsets, and the Fairy type
-- did not exist then.  The only Fairy moves that fall out of that dataset are
-- CHARM, MOONLIGHT and SWEET_KISS -- all three power 0.  So Fairy worked
-- defensively (resistances, the Dragon immunity) while nothing could attack
-- WITH it, which makes the type half-real.
--
-- These five are the standard Gen 6 Fairy attacking set.  Each reuses an
-- existing Gen 1 animation, same as every other added move: there is no new
-- art here, only a sensible read.  Nothing learns them by level-up yet -- they
-- arrive via the dummy starter test and are available for hand-authoring onto
-- Fairy species' learnsets later.
return {
  FAIRY_WIND = {
    id = "FAIRY_WIND", name = "FAIRY WIND", type = "FAIRY",
    power = 40, accuracy = 100, pp = 30,
    effect = "NO_ADDITIONAL_EFFECT", anim = "GUST", category = "special",
  },
  DRAINING_KISS = {
    id = "DRAINING_KISS", name = "DRAININGKISS", type = "FAIRY",
    power = 50, accuracy = 100, pp = 10,
    effect = "DRAIN_HP_EFFECT", anim = "ABSORB", category = "special",
  },
  DAZZLING_GLEAM = {
    id = "DAZZLING_GLEAM", name = "DAZZLNGGLEAM", type = "FAIRY",
    power = 80, accuracy = 100, pp = 10,
    effect = "NO_ADDITIONAL_EFFECT", anim = "SWIFT", category = "special",
  },
  PLAY_ROUGH = {
    id = "PLAY_ROUGH", name = "PLAY ROUGH", type = "FAIRY",
    power = 90, accuracy = 90, pp = 10,
    effect = "ATTACK_DOWN1_EFFECT", anim = "SLAM", category = "physical",
  },
  MOONBLAST = {
    id = "MOONBLAST", name = "MOONBLAST", type = "FAIRY",
    power = 95, accuracy = 100, pp = 15,
    effect = "SPECIAL_DOWN1_EFFECT", anim = "SWIFT", category = "special",
  },
}
