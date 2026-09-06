--!strict
-- Sprite catalogue for the "Essential UI Pack" (Swarve Studios), read out of
-- the pack's own demo place. Plain rbxassetid strings, no Roblox datatypes,
-- same arrangement as `Icons` -- and the same warning applies: a Creator Store
-- id can be moderated and vanish, so anything that draws one of these keeps a
-- procedural look underneath to fall back to (see `Theme.chunky`'s Plate).
--
-- HOW THESE BEHAVE, because it decides where they can be used at all:
--
--  * There is no 9-slice in the pack -- not one image sets a SliceCenter, and
--    Roblox will not hand out the source dimensions of an asset the account
--    does not own, so none can be added blind. Every sprite is therefore
--    STRETCHED to its frame, and stretching is only invisible near the
--    sprite's own aspect. Measured in game: a plate reads correctly from
--    about 3:1 to 6:1, smears past 9:1, and is unusable square.
--
--  * Only `Plate.Neutral` and the bars take a tint. The coloured plates carry
--    their colour in the pixels, so an ImageColor3 on top MULTIPLIES with it
--    -- a blue tint on the pink square gives purple mud, which is exactly how
--    the square tiles were tried and rejected.
--
-- Tinting Neutral with the caller's own Theme.Function colour is what keeps
-- "one colour per function" intact: the colour still comes from the theme, the
-- pack only supplies the texture and the relief.

local UIPack = {}

-- Wide button faces. Neutral is the one to reach for; the coloured ones are
-- here for a face that wants the pack's own saturation rather than a tint.
UIPack.Plate = {
	Neutral = "rbxassetid://110828187234554", -- silver, tints cleanly
	Green = "rbxassetid://87326447332057",
	GreenSoft = "rbxassetid://100506345795869",
	Gold = "rbxassetid://139418228897608",
	GoldSoft = "rbxassetid://82312491077959",
	Golden = "rbxassetid://115624555582768",
	Cyan = "rbxassetid://131798641019550",
	Red = "rbxassetid://92958786684902",
	Rainbow = "rbxassetid://105351427848376",
}

-- Window headers. Much longer than a plate (about 9:1), which is why they are
-- a separate family rather than a thinner plate.
UIPack.Bar = {
	Blue = "rbxassetid://100627035489276",
	Gold = "rbxassetid://131343092776040",
	Purple = "rbxassetid://120692375639753",
}

-- The only square face in the pack. Pink in the pixels -- it is the close
-- button of the pack's own windows, and it does not tint.
UIPack.Square = { Pink = "rbxassetid://86216771097425" }

-- Decoration. Sunburst goes BEHIND something that has just been won; Glow is a
-- soft radial; Card is a near-white noise panel; Disc is a flat black round.
UIPack.Decor = {
	Sunburst = "rbxassetid://101335357428300",
	Glow = "rbxassetid://131708002708097",
	Card = "rbxassetid://120342677944790",
	Disc = "rbxassetid://108336300645944",
}

-- Artwork. Mostly overlapping with `Icons`, kept for the few this pack does
-- better -- the cash stacks and the wheel especially.
UIPack.Art = {
	CashStack = "rbxassetid://77319404533832",
	CashBundle = "rbxassetid://119496692548587",
	Chest = "rbxassetid://97493315422791",
	Muscle = "rbxassetid://87652362787600",
	Book = "rbxassetid://138787751104353",
	Cube = "rbxassetid://127408013806229",
	Question = "rbxassetid://130412104971687",
	Face = "rbxassetid://72230557461051",
	Wheel = "rbxassetid://15961470200",
	WheelAlt = "rbxassetid://138297996642417",
	Refresh = "rbxassetid://127981244153803",
	ArrowUp = "rbxassetid://139223624814827",
	ArrowPlay = "rbxassetid://88353043959572",
	Pointer = "rbxassetid://94539448210782",
}

return UIPack
