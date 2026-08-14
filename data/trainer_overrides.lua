-- Hand-authored gym leader and Elite Four rosters.  SAFE TO EDIT.
--
-- Each entry is a full replacement party: { level, "SPECIES" } in order.  They
-- are written out in full rather than as a diff because a leader's team is a
-- designed thing -- reading the whole list is how you check it, and a diff
-- would hide what the fight actually looks like.
--
-- Vanilla teams are quoted above each one (from pret/pokered
-- data/trainers/parties.asm) so every change is visible in context.
--
-- Levels are kept at their vanilla values wherever a slot is unchanged, and
-- new slots are levelled INSIDE the existing band rather than above it: the
-- point is more variety, not a harder game.
--
-- Giovanni has three parties in one trainer entry (two overworld fights and
-- the gym), which is why his value is a list of lists.
return {
  -- 12 GEODUDE, 14 ONIX
  OPP_BROCK = {
    { { 12, "GEODUDE" }, { 13, "ARON" }, { 14, "ONIX" } },
  },
  -- 18 STARYU, 21 STARMIE
  OPP_MISTY = {
    { { 18, "STARYU" }, { 19, "CHINCHOU" }, { 21, "STARMIE" } },
  },
  -- 21 VOLTORB, 18 PIKACHU, 24 RAICHU
  OPP_LT_SURGE = {
    { { 21, "VOLTORB" }, { 18, "PIKACHU" }, { 21, "ELEKID" },
      { 24, "RAICHU" } },
  },
  -- 29 VICTREEBEL, 24 TANGELA, 29 VILEPLUME
  OPP_ERIKA = {
    { { 24, "TANGELA" }, { 27, "SUNFLORA" }, { 29, "VICTREEBEL" },
      { 29, "VILEPLUME" } },
  },
  -- 37 KOFFING, 39 MUK, 37 KOFFING, 43 WEEZING
  -- both Koffing replaced: Qwilfish and Seviper
  OPP_KOGA = {
    { { 37, "QWILFISH" }, { 39, "MUK" }, { 37, "SEVIPER" },
      { 43, "WEEZING" } },
  },
  -- 42 GROWLITHE, 40 PONYTA, 42 RAPIDASH, 47 ARCANINE
  -- Growlithe and Ponyta replaced, plus one new
  OPP_BLAINE = {
    { { 40, "TORKOAL" }, { 42, "HOUNDOOM" }, { 42, "RAPIDASH" },
      { 43, "DARMANITAN" }, { 47, "ARCANINE" } },
  },
  -- 38 KADABRA, 37 MR_MIME, 38 VENOMOTH, 43 ALAKAZAM
  -- Kadabra and Venomoth replaced
  OPP_SABRINA = {
    { { 37, "MR_MIME" }, { 38, "GIRAFARIG" }, { 38, "XATU" },
      { 43, "ALAKAZAM" } },
  },
  -- fight 1: 25 ONIX, 24 RHYHORN, 29 KANGASKHAN
  -- fight 2: 37 NIDORINO, 35 KANGASKHAN, 37 RHYHORN, 41 NIDOQUEEN
  -- gym:     45 RHYHORN, 42 DUGTRIO, 44 NIDOQUEEN, 45 NIDOKING, 50 RHYDON
  --
  -- Kangaskhan is not a Ground type and never fit the Ground-specialist gym.
  -- Krokorok replaces it in both overworld fights and joins the gym team, so
  -- the same face recurs the way Giovanni's Rhyhorn line does.  Ground/Dark
  -- also suits a crime boss.  The gym Rhyhorn becomes Hippowdon, leaving
  -- Rhydon as the line's payoff.
  OPP_GIOVANNI = {
    { { 25, "ONIX" }, { 24, "RHYHORN" }, { 29, "KROKOROK" } },
    { { 37, "NIDORINO" }, { 35, "KROKOROK" }, { 37, "RHYHORN" },
      { 41, "NIDOQUEEN" } },
    { { 42, "DUGTRIO" }, { 44, "NIDOQUEEN" }, { 45, "KROKOROK" },
      { 45, "HIPPOWDON" }, { 45, "NIDOKING" }, { 50, "RHYDON" } },
  },
  -- 54 DEWGONG, 53 CLOYSTER, 54 SLOWBRO, 56 JYNX, 56 LAPRAS
  -- Slowbro replaced with an Ice type, plus one new
  OPP_LORELEI = {
    { { 53, "CLOYSTER" }, { 54, "DEWGONG" }, { 54, "WALREIN" },
      { 55, "FROSLASS" }, { 56, "JYNX" }, { 56, "LAPRAS" } },
  },
  -- 53 ONIX, 55 HITMONCHAN, 55 HITMONLEE, 56 ONIX, 58 MACHAMP
  -- both Onix replaced with Fighting types, plus one new.  Hitmontop
  -- completes the Hitmon trio, which is what Bruno's team was always
  -- gesturing at.
  OPP_BRUNO = {
    { { 53, "HARIYAMA" }, { 55, "HITMONCHAN" }, { 55, "HITMONLEE" },
      { 56, "HITMONTOP" }, { 57, "SCRAFTY" }, { 58, "MACHAMP" } },
  },
  -- 56 GENGAR, 56 GOLBAT, 55 HAUNTER, 58 ARBOK, 60 GENGAR
  -- one Gengar and the Haunter stay; the other three go, plus one new.
  -- Golbat and Arbok were never Ghosts, which is half of why her team read
  -- as filler.
  OPP_AGATHA = {
    { { 55, "HAUNTER" }, { 56, "MISDREAVUS" }, { 56, "DRIFBLIM" },
      { 57, "MISMAGIUS" }, { 58, "SPIRITOMB" }, { 60, "GENGAR" } },
  },
  -- 58 GYARADOS, 56 DRAGONAIR, 56 DRAGONAIR, 60 AERODACTYL, 62 DRAGONITE
  -- both Dragonair replaced: Flygon and Druddigon.  Plus one new.
  OPP_LANCE = {
    { { 56, "FLYGON" }, { 56, "DRUDDIGON" }, { 58, "GYARADOS" },
      { 60, "AERODACTYL" }, { 60, "KINGDRA" }, { 62, "DRAGONITE" } },
  },
}
