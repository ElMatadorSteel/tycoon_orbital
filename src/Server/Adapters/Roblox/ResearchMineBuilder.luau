--!strict
-- Builds the research mine: the tycoon pad at the edge of a player's deck,
-- and the extension that pad opens -- a gangway out into the void and an
-- open-pit quarry cut into a captured asteroid.
--
-- Geometry only. This module decides nothing: it neither reads a profile nor
-- charges anything, and the pad it returns is wired to a use case by
-- StationSceneBuilder (which owns the pad -> owner mapping) rather than
-- here. That is the split RailgunKioskBuilder does NOT have -- it reaches
-- into the profile repository from inside a Touched handler -- and the
-- reason not to copy it is that the pad here has to be able to REFUSE, which
-- means the decision has to come back out to something that can answer.
--
-- An OPEN pit rather than tunnels, deliberately: a hollow interior cannot be
-- built out of boxes without either CSG or a mesh, and neither survives a
-- rebuild from source (see StationSceneBuilder's note on ModuleModels). A
-- terraced quarry is the same silhouette in parts a script can reproduce.
--
-- Everything is expressed in PLOT-ORIGIN space: the origin's XZ plane is the
-- deck's walking surface (y = 0) and +Z points away from the lobby, which is
-- where there is room. All plot origins are axis-aligned (Domain/Plots/
-- Layout builds them with no rotation), so "+Z" is the same direction for
-- every player and the extensions cannot swing into one another.

-- fromShared(path) reaches ReplicatedStorage.Shared directly: Rojo maps
-- src/Server and src/Shared to different service roots with no common
-- ancestor a relative "../.." path can reach. Lune has no `game`, so the
-- fallback below -- an ordinary relative require -- is what runs there.
local function fromShared(path: string): any
	if game then
		local node: any = (game :: any):GetService("ReplicatedStorage").Shared
		for segment in path:gmatch("[^/]+") do
			node = node[segment]
		end
		return node
	end
	return "../../../Shared/" .. path
end

local OreCatalog = require(fromShared("Domain/Research/OreCatalog"))

type Ore = OreCatalog.Ore

----------------------------------------------------------------------
-- Shape, not balance
--
-- Dimensions live here rather than in Shared/Balance for the same reason
-- Domain/Plots/Layout keeps its own jitter constants: nobody retunes these
-- to change how the game plays, they are what the thing looks like. The one
-- number that IS balance -- the price -- is handed in.

-- The whole extension shares one upper walking plane. It clears the deck's
-- rim (3 studs) and the neon strip along its top (3.2) rather than matching
-- either: geometry that shares a face with what it sits on gives the depth
-- buffer two surfaces at one depth, and the result flickers as the camera
-- moves. Every "sits on top of" in this file is therefore a small deliberate
-- overlap, never a touch.
local WALK_Y = 3.4
local SEAT = 0.1 -- how far a thing sinks into whatever it stands on

local STEP_WIDTH = 12
local LANDING_DEPTH = 20
local PAD_SIZE = 8

local BRIDGE_WIDTH = 12
local BRIDGE_SEGMENT = 22

-- Distance from the plot origin to the middle of the pit. Short enough that
-- the two nearest plots (about 150 studs apart in X, and 65 studs apart in
-- altitude) keep their extensions clear of each other, long enough that the
-- mine reads as somewhere you travel to.
local MINE_DISTANCE = 220
local MINE_RADIUS = 90
local RING_SEGMENTS = 24
local ROCK_THICKNESS = 14
local TERRACE_DROP = 12

-- outer/inner radius and walking height of each terrace, rim first. Heights
-- hang off WALK_Y so the gangway arrives level with the top one.
local TERRACES = {
	{ outer = 90, inner = 66, top = WALK_Y },
	{ outer = 66, inner = 44, top = WALK_Y - TERRACE_DROP },
	{ outer = 44, inner = 24, top = WALK_Y - TERRACE_DROP * 2 },
}
local FLOOR_RADIUS = 28
local FLOOR_THICKNESS = 12
local FLOOR_TOP = WALK_Y - TERRACE_DROP * 3

-- Relief between neighbouring ring segments. Keyed off the segment INDEX, not
-- off the hash below: hashed offsets are unrelated numbers that occasionally
-- land within a thousandth of each other, and "occasionally coplanar" is a
-- flicker that shows up on one player's station and not the reviewer's. Fixed
-- steps guarantee any two overlapping segments differ.
--
-- Four levels, not three. Two segments share a level every RELIEF_LEVELS
-- steps, so the cycle length sets how far apart same-height segments are: at
-- three (45 degrees) the innermost ring's segments are deep enough relative
-- to their radius that they still just reached each other. Four puts them 60
-- degrees apart, clear on every ring. RING_SEGMENTS is a multiple of it, so
-- the seam at step 0 works out too.
local SEGMENT_RELIEF = 0.07
local RELIEF_LEVELS = 4

local STAIR_STEPS = 6
local STAIR_RISE = 2 -- drop from a terrace to its first tread
local STAIR_LIFT = 0.2 -- treads sit proud of the terrace they land on
local STAIR_WIDTHS = { 14, 12, 10 }
-- How far each flight travels inward. The last one is shorter than the others
-- on purpose: at a full run it landed 6 studs from the pit centre, which is
-- inside the drill standing there -- the stairs have to arrive BESIDE the
-- machine, not underneath it.
local STAIR_RUNS = { 18, 18, 11 }

-- Radius of the drill's plinth. Sized to the model that stands on it (about
-- 19 x 20 studs) with a little margin, and small enough that the foot of the
-- staircase clears it.
local DRILL_PAD_RADIUS = 11
-- The descent runs down the -Z side, in line with the gangway: one straight
-- read from the entrance to the drill site, rather than a scavenger hunt.
local STAIR_ANGLE = math.pi

-- Angles the veins outcrop at, in degrees. The stairs come in at 180 and the
-- research post sits at 90; these four avoid both.
local VEIN_ANGLES = { 30, 115, 215, 305 }

-- Where the shovel pad stands on the rim terrace. Clear of the stairs (180),
-- the research post (90) and every vein angle above, with the widest gap it
-- can get from all of them.
local SHOVEL_ANGLE = 145

local PALETTE = {
	Rock = Color3.fromRGB(84, 78, 74),
	RockDark = Color3.fromRGB(61, 57, 55),
	RockLight = Color3.fromRGB(104, 97, 90),
	Structure = Color3.fromRGB(78, 86, 104),
	Trim = Color3.fromRGB(72, 214, 255),
	PadLocked = Color3.fromRGB(255, 176, 60),
	PadOpen = Color3.fromRGB(80, 226, 128),
	PadRefused = Color3.fromRGB(255, 82, 82),
}

----------------------------------------------------------------------

local function part(parent: Instance, name: string, props: { [string]: any }): BasePart
	local instance = Instance.new("Part")
	instance.Name = name
	instance.Anchored = true
	instance.CanCollide = true
	instance.CastShadow = false
	instance.TopSurface = Enum.SurfaceType.Smooth
	instance.BottomSurface = Enum.SurfaceType.Smooth
	instance.Material = Enum.Material.Slate
	instance.Color = PALETTE.Rock
	for key, value in props do
		(instance :: any)[key] = value
	end
	instance.Parent = parent
	return instance
end

-- A deterministic hash in [0, 1). Not Random.new(): this adapter is built
-- headlessly under Lune to check its geometry (see the repository notes on
-- verifying adapters without Studio), and the fewer Roblox datatypes it
-- needs to do that, the better. Deterministic also means two players' mines
-- are cut the same way, which is what makes them comparable.
local function hash(a: number, b: number): number
	local value = math.sin(a * 12.9898 + b * 78.233) * 43758.5453
	return value - math.floor(value)
end

local function colourOf(ore: Ore): Color3
	return Color3.fromRGB(ore.colour.R, ore.colour.G, ore.colour.B)
end

-- "2500" -> "2 500". Narrow no-break space, so a price never wraps in the
-- middle of itself on a billboard.
local function money(amount: number): string
	local text = tostring(math.floor(amount))
	local grouped = text
	while true do
		local replaced, count = grouped:gsub("^(-?%d+)(%d%d%d)", "%1\u{202F}%2")
		grouped = replaced
		if count == 0 then
			break
		end
	end
	return grouped .. " \u{00A2}"
end

-- `height` is how far above `host`'s CENTRE the sign floats. A parameter
-- rather than a constant because one of these hangs over a machine 19 studs
-- tall: a fixed offset put the text inside the drill.
--
-- The sign hangs from an ANCHOR of its own, placed at the exact spot the text
-- belongs, with no offset left to apply. StudsOffsetWorldSpace did NOT put
-- the text where the arithmetic said it would on the drill's plinth -- that
-- adornee is a cylinder turned 90 degrees, and the sign came out beside and
-- below the machine rather than above it, even with the property reading the
-- right number. An invisible axis-aligned anchor has no such question to
-- answer: the sign is where the anchor is, and the anchor's position is one
-- number anyone can check.
local function label(host: BasePart, title: string, subtitle: string, height: number?): BillboardGui
	local anchor = Instance.new("Part")
	anchor.Name = "SignAnchor"
	anchor.Size = Vector3.new(0.2, 0.2, 0.2)
	anchor.Transparency = 1
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.CastShadow = false
	anchor.CFrame = CFrame.new(host.Position + Vector3.new(0, height or 5, 0))
	anchor.Parent = host

	local gui = Instance.new("BillboardGui")
	gui.Name = "Sign"
	gui.Size = UDim2.fromScale(11, 3.2)
	-- Depth-tested, not drawn over everything: these hang inside a pit, and a
	-- sign that shows through 40 studs of rock stops reading as a sign on a
	-- machine and starts reading as a HUD element.
	gui.AlwaysOnTop = false
	gui.MaxDistance = 420
	gui.Parent = anchor
	gui.Adornee = anchor

	local heading = Instance.new("TextLabel")
	heading.Name = "Title"
	heading.BackgroundTransparency = 1
	heading.Size = UDim2.fromScale(1, 0.58)
	heading.Font = Enum.Font.GothamBold
	heading.TextScaled = true
	heading.TextColor3 = Color3.fromRGB(255, 255, 255)
	heading.TextStrokeTransparency = 0.4
	heading.Text = title
	heading.Parent = gui

	local detail = Instance.new("TextLabel")
	detail.Name = "Detail"
	detail.BackgroundTransparency = 1
	detail.Position = UDim2.fromScale(0, 0.58)
	detail.Size = UDim2.fromScale(1, 0.42)
	detail.Font = Enum.Font.GothamMedium
	detail.TextScaled = true
	detail.TextColor3 = PALETTE.Trim
	detail.TextStrokeTransparency = 0.5
	detail.Text = subtitle
	detail.Parent = gui

	return gui
end

local function pointLight(host: BasePart, colour: Color3, range: number, brightness: number)
	local light = Instance.new("PointLight")
	light.Color = colour
	light.Range = range
	light.Brightness = brightness
	light.Parent = host
end

----------------------------------------------------------------------
-- The access pad -- built with the plot, long before it is affordable

-- The steps climb the deck's own rim: a 3-stud wall with a 1.6-stud footprint
-- is exactly the height a Humanoid catches on rather than walks over, and a
-- pad you can see but not reach reads as a bug.
--
-- Two steps of 1.5, not three of 1: the deck IS the build grid, edge to
-- edge, so every stud a step reaches inland is a stud a module can be placed
-- on top of. Two steps put all but the last 2 studs outside the outermost
-- row. Placement itself still knows nothing about them -- reserving those
-- cells is a Domain change, and this is a 12-stud notch in a 200-stud deck.
local function buildApproach(parent: Instance, origin: CFrame, half: number)
	-- Each step is sunk half a stud below the deck rather than resting on it:
	-- a step whose underside is exactly the deck's surface is two coplanar
	-- faces, and the top one wins only until the camera moves. The upper step
	-- swallows the rim and its neon strip whole for the same reason.
	for index = 1, 2 do
		local top = index * (WALK_Y / 2)
		part(parent, "MineStep", {
			Size = Vector3.new(STEP_WIDTH, top + 0.5, 4),
			CFrame = origin * CFrame.new(0, (top - 0.5) / 2, half - 8 + index * 4),
			Color = PALETTE.Structure,
			Material = Enum.Material.Metal,
		})
	end

	-- Butts against the upper step at half + 2 instead of running under it:
	-- two treads sharing a plane where they overlap is the same fault again.
	part(parent, "MineLanding", {
		Size = Vector3.new(STEP_WIDTH + 6, 1, LANDING_DEPTH),
		CFrame = origin * CFrame.new(0, WALK_Y - 0.5, half + 2 + LANDING_DEPTH / 2),
		Color = PALETTE.Structure,
		Material = Enum.Material.DiamondPlate,
	})
end

export type PadHandle = {
	pad: BasePart,
	sign: BillboardGui,
	-- What the sign says once it has been paid for. Carried on the handle so
	-- markUnlocked does not have to know which pad it was handed.
	openText: string,
}

-- The tile itself, shared by both pads: the neon square, its four posts, its
-- light and its sign. Extracted when the shovel got a pad of its own -- two
-- copies of this would drift the first time either is restyled.
--
-- `centre` is the world CFrame of the pad's middle; everything else hangs off
-- it, so a caller only has to know where the pad goes, not how one is built.
local function padTile(
	parent: Instance,
	name: string,
	centre: CFrame,
	title: string,
	subtitle: string,
	openText: string
): PadHandle
	local pad = part(parent, name, {
		Size = Vector3.new(PAD_SIZE, 0.6, PAD_SIZE),
		CFrame = centre,
		Color = PALETTE.PadLocked,
		Material = Enum.Material.Neon,
		CanCollide = true,
	})
	pointLight(pad, PALETTE.PadLocked, 18, 1.6)

	-- Four corner posts, so the pad reads as a mechanism rather than as a
	-- coloured tile someone forgot to delete.
	for _, dx in { -1, 1 } do
		for _, dz in { -1, 1 } do
			part(parent, "PadPost", {
				Size = Vector3.new(0.8, 3.4, 0.8),
				CFrame = centre
					* CFrame.new(dx * (PAD_SIZE / 2 + 0.6), 1.4, dz * (PAD_SIZE / 2 + 0.6)),
				Color = PALETTE.Structure,
				Material = Enum.Material.Metal,
				CanCollide = false,
			})
		end
	end

	return { pad = pad, sign = label(pad, title, subtitle), openText = openText }
end

local ResearchMineBuilder = {}

-- Returns the pad rather than wiring it: who owns this plot, and what
-- stepping on it should cost, are not this module's business.
function ResearchMineBuilder.buildAccessPad(
	parent: Instance,
	origin: CFrame,
	span: number,
	cost: number
): PadHandle
	local half = span / 2
	buildApproach(parent, origin, half)

	return padTile(
		parent,
		"ResearchMinePad",
		origin * CFrame.new(0, WALK_Y + 0.3 - SEAT, half + 2 + LANDING_DEPTH / 2),
		"ZONE DE RECHERCHE",
		money(cost),
		"Ouverte"
	)
end

-- The shovel's pad, INSIDE the mine rather than up on the deck: it is the
-- tool you dig this pit with, so the place you buy it is the pit. Built with
-- the zone, so it cannot be stood on before the mine itself is paid for --
-- which is also why it needs no unlock check of its own to be unreachable.
function ResearchMineBuilder.buildShovelPad(
	parent: Instance,
	origin: CFrame,
	span: number,
	cost: number
): PadHandle
	local terrace = TERRACES[1]
	local radius = (terrace.outer + terrace.inner) / 2
	local angle = math.rad(SHOVEL_ANGLE)

	-- Sunk past the deepest a ring segment's relief can cut, so the tile
	-- never floats over the rock it sits on (see SEGMENT_RELIEF).
	local centre = origin
		* CFrame.new(
			math.sin(angle) * radius,
			terrace.top - 0.05,
			(span / 2 + MINE_DISTANCE) + math.cos(angle) * radius
		)

	return padTile(parent, "ShovelPad", centre, "PELLE", money(cost), "Achetée")
end

-- The tool itself. An authored model when one has been placed at
-- ReplicatedStorage.ResearchModels.Shovel -- same arrangement as the Drill
-- and the mineral clusters, and the same caveat (see drillTemplate's note:
-- an authored asset lives only in the place file and cannot be rebuilt from
-- the repository). The original stick-and-blade below is kept as the
-- fallback rather than deleted: a shovel is cheap enough to write that a
-- missing asset should never leave the mine without one.
function ResearchMineBuilder.buildShovelTool(): Tool
	local tool = Instance.new("Tool")
	tool.Name = "Pelle"
	tool.RequiresHandle = true
	tool.CanBeDropped = false
	tool.ToolTip = "Creuser un filon"

	local shovelFolder = if game
		then (game :: any):GetService("ReplicatedStorage"):FindFirstChild("ResearchModels")
		else nil
	local shovelTemplate = shovelFolder and shovelFolder:FindFirstChild("Shovel")

	if
		shovelTemplate
		and shovelTemplate:IsA("Model")
		and shovelTemplate:FindFirstChild("Handle")
	then
		local clone = shovelTemplate:Clone()
		local authored = clone:FindFirstChild("Handle") :: BasePart

		-- Welded while the parts still sit at the offsets the model was
		-- authored with -- a WeldConstraint freezes the offset its two parts
		-- have at the moment it is enabled, so welding after moving anything
		-- would bake in the wrong pose. Massless keeps a 4-stud shovel from
		-- changing how the character walks.
		for _, descendant in clone:GetDescendants() do
			if descendant:IsA("BasePart") then
				descendant.Anchored = false
				descendant.CanCollide = false
				descendant.Massless = true
				if descendant ~= authored then
					local joint = Instance.new("WeldConstraint")
					joint.Part0 = authored
					joint.Part1 = descendant
					joint.Parent = authored
				end
			end
		end

		-- A Tool requires its Handle to be a DIRECT child, so the model is
		-- unwrapped rather than parented whole.
		for _, child in clone:GetChildren() do
			child.Parent = tool
		end
		clone:Destroy()

		-- Held at the side, shaft upright, blade down by the feet. Found by
		-- looking at it in a running session rather than derived: the model's
		-- long axis is its local Y and the blade hangs at -Y, so any rotation
		-- about X lays the shovel flat like a rifle. A positive Grip.Y lowers
		-- the tool, since Handle.CFrame = hand * Grip:Inverse().
		tool.Grip = CFrame.new(0, 0.35, 0) * CFrame.Angles(math.rad(-12), 0, 0)
		return tool
	end

	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.new(0.4, 4.6, 0.4)
	handle.Color = Color3.fromRGB(122, 88, 58)
	handle.Material = Enum.Material.Wood
	handle.CanCollide = false
	handle.Parent = tool

	local blade = Instance.new("Part")
	blade.Name = "Blade"
	blade.Size = Vector3.new(1.9, 2.2, 0.25)
	blade.Color = PALETTE.Structure
	blade.Material = Enum.Material.Metal
	blade.CanCollide = false
	-- Positioned BEFORE the weld: a WeldConstraint freezes the offset the two
	-- parts have at the moment it is enabled, so moving one afterwards drags
	-- the other with it instead of correcting the join.
	blade.CFrame = handle.CFrame * CFrame.new(0, -2.4, 0)
	blade.Parent = tool

	local weld = Instance.new("WeldConstraint")
	weld.Part0 = handle
	weld.Part1 = blade
	weld.Parent = handle

	return tool
end

----------------------------------------------------------------------
-- The zone -- built once, the moment the pad is paid for

local function buildGangway(model: Model, origin: CFrame, half: number, centreZ: number)
	local startZ = half + 2 + LANDING_DEPTH
	local endZ = centreZ - MINE_RADIUS
	local length = endZ - startZ
	local count = math.max(1, math.round(length / BRIDGE_SEGMENT))
	local segment = length / count
	local middle = startZ + length / 2

	-- Alternating plates, so the walk has a rhythm and the length is
	-- legible from the deck rather than reading as one endless slab. They
	-- butt exactly rather than overlapping: an overlap between two plates of
	-- equal height is a shared top face, and five of those down the middle
	-- of the walkway is a strip of flicker you cross on the way in.
	for index = 1, count do
		part(model, "Gangway", {
			Size = Vector3.new(BRIDGE_WIDTH, 1, segment),
			CFrame = origin * CFrame.new(0, WALK_Y - 0.5, startZ + (index - 0.5) * segment),
			Color = if index % 2 == 0 then PALETTE.Structure else PALETTE.RockDark,
			Material = Enum.Material.DiamondPlate,
		})
	end

	-- Spine and rails run the full length as single parts: a dozen short
	-- beams butted end to end show every seam, one long one shows none.
	part(model, "GangwaySpine", {
		Size = Vector3.new(3.4, 2.4, length),
		CFrame = origin * CFrame.new(0, WALK_Y - 2.1, middle),
		Color = PALETTE.Structure,
		Material = Enum.Material.Metal,
		CanCollide = false,
	})

	for _, side in { -1, 1 } do
		part(model, "GangwayRail", {
			Size = Vector3.new(0.6, 3, length),
			CFrame = origin
				* CFrame.new(side * (BRIDGE_WIDTH / 2 - 0.3), WALK_Y + 1.5 - SEAT, middle),
			Color = PALETTE.Structure,
			Material = Enum.Material.Metal,
		})
		part(model, "GangwayGlow", {
			Size = Vector3.new(0.35, 0.35, length),
			CFrame = origin * CFrame.new(side * (BRIDGE_WIDTH / 2 - 0.3), WALK_Y + 2.85, middle),
			Color = PALETTE.Trim,
			Material = Enum.Material.Neon,
			CanCollide = false,
			CanQuery = false,
		})
	end

	-- A lamp roughly every 40 studs. The pit is lit and the deck is lit; the
	-- void between them is not, and an unlit gangway is one you walk off.
	local lamps = math.max(2, math.floor(length / 40))
	for index = 0, lamps do
		local z = startZ + (length / lamps) * index
		-- On the rail line, not beside it: at the old offset the posts stood
		-- half a stud off the edge of the walkway with nothing under them.
		part(model, "GangwayPost", {
			Size = Vector3.new(0.7, 7, 0.7),
			CFrame = origin * CFrame.new(-(BRIDGE_WIDTH / 2 - 0.3), WALK_Y + 3.4 - SEAT, z),
			Color = PALETTE.Structure,
			Material = Enum.Material.Metal,
			CanCollide = false,
		})
		local bulb = part(model, "GangwayLamp", {
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(1.4, 1.4, 1.4),
			CFrame = origin * CFrame.new(-(BRIDGE_WIDTH / 2 - 0.3), WALK_Y + 7.2, z),
			Color = PALETTE.Trim,
			Material = Enum.Material.Neon,
			CanCollide = false,
			CanQuery = false,
		})
		pointLight(bulb, PALETTE.Trim, 26, 1.2)
	end
end

local function buildEntrance(model: Model, origin: CFrame, centreZ: number)
	local z = centreZ - MINE_RADIUS + 4

	for _, side in { -1, 1 } do
		part(model, "ArchPillar", {
			Size = Vector3.new(3, 16, 3),
			CFrame = origin * CFrame.new(side * 10, WALK_Y + 8 - SEAT * 2, z),
			Color = PALETTE.Structure,
			Material = Enum.Material.Metal,
		})
	end

	local lintel = part(model, "ArchLintel", {
		Size = Vector3.new(26, 3, 3),
		CFrame = origin * CFrame.new(0, WALK_Y + 17.5, z),
		Color = PALETTE.Structure,
		Material = Enum.Material.Metal,
		CanCollide = false,
	})
	part(model, "ArchGlow", {
		Size = Vector3.new(24, 0.5, 0.5),
		CFrame = origin * CFrame.new(0, WALK_Y + 15.6, z),
		Color = PALETTE.Trim,
		Material = Enum.Material.Neon,
		CanCollide = false,
		CanQuery = false,
	})
	pointLight(lintel, PALETTE.Trim, 42, 2)

	-- Read off the catalogue rather than spelled out: the sign at the door
	-- and the veins inside cannot then disagree about what is in there.
	local names = {}
	for _, ore in OreCatalog.Ores do
		table.insert(names, ore.name)
	end
	label(lintel, "MINE DE RECHERCHE", table.concat(names, " \u{00B7} "))
end

local function buildTerrace(model: Model, origin: CFrame, centreZ: number, index: number)
	local terrace = TERRACES[index]
	local mid = (terrace.outer + terrace.inner) / 2
	local depth = terrace.outer - terrace.inner
	-- A segment has to span the chord at its OUTER radius, which is where
	-- neighbours are furthest apart -- sizing off the arc at the MID radius
	-- leaves wedge-shaped gaps along the outer edge, worst on the tightest
	-- ring (terrace 3 was 11% holes). Overlap costs nothing now: the relief
	-- below is what keeps neighbours from sharing a top plane, so the width
	-- is free to be whatever actually closes the ring.
	local width = 2 * terrace.outer * math.sin(math.pi / RING_SEGMENTS) * 1.08

	for step = 0, RING_SEGMENTS - 1 do
		local angle = (step / RING_SEGMENTS) * math.pi * 2
		-- Segment-by-segment wobble: 24 identical boxes in a circle read as a
		-- cog, not as rock. It only ever grows a segment OUTWARD (the radial
		-- centre moves with the extra depth), because the inner face is the
		-- wall the terrace below butts against -- letting that one wander
		-- would open slits between the rings.
		local wobble = hash(step, index)
		local thickness = ROCK_THICKNESS + wobble * 3
		-- Neighbours still overlap, so they must not share a top plane. Three
		-- fixed levels cycling by index: any two adjacent segments differ, and
		-- the two that share a level are 60 degrees apart and never touch.
		-- 24 is a multiple of 3, so the seam at step 0 works out too.
		-- Levels start at 1, never 0: at zero relief the outermost ring sat
		-- exactly level with the gangway that lands on it, which is the same
		-- fight one part further out.
		local top = terrace.top - (step % RELIEF_LEVELS + 1) * SEGMENT_RELIEF

		part(model, `Terrace{index}`, {
			Size = Vector3.new(width, thickness, depth + wobble * 2),
			CFrame = origin * CFrame.new(
				math.sin(angle) * (mid + wobble),
				top - thickness / 2,
				centreZ + math.cos(angle) * (mid + wobble)
			) * CFrame.Angles(0, angle, 0),
			Color = if wobble > 0.62
				then PALETTE.RockLight
				elseif wobble > 0.3 then PALETTE.Rock
				else PALETTE.RockDark,
		})
	end
end

-- One flight, resting on the terrace it lands on: each step is a solid block
-- from below that terrace's underside up to its own tread, so no step can
-- float when the wobble above happens to cut deeper than expected. Treads sit
-- STAIR_LIFT proud of the terrace they land on -- clear of the segment relief
-- above, so the last tread and the rock it meets are never the same plane.
local function buildStairs(
	model: Model,
	origin: CFrame,
	centreZ: number,
	fromRadius: number,
	toRadius: number,
	firstTop: number,
	lastTop: number,
	baseY: number,
	width: number
)
	local drop = (lastTop - firstTop) / (STAIR_STEPS - 1)
	local run = (fromRadius - toRadius) / STAIR_STEPS

	for index = 1, STAIR_STEPS do
		local top = firstTop + drop * (index - 1) + STAIR_LIFT
		local radius = fromRadius - (index - 0.5) * run
		part(model, "PitStep", {
			Size = Vector3.new(width, top - baseY, run + 0.4),
			CFrame = origin * CFrame.new(
				math.sin(STAIR_ANGLE) * radius,
				(top + baseY) / 2,
				centreZ + math.cos(STAIR_ANGLE) * radius
			),
			Color = PALETTE.RockLight,
			Material = Enum.Material.Rock,
		})
	end
end

-- The attributes are the point of this function, not the crystals: the
-- digging that comes next needs to know what it just hit, and a vein whose
-- ore is implied by its colour is a vein no rule can read.
--
-- `terrace`/`slot` are what a client's raycast turns back into
-- OreCatalog.veinId(terrace, slot) -- the network id MineVein validates a
-- claimed hit against. Stamped alongside the ore's own attributes rather
-- than in place of them: OreId/Rarity/Hardness/Value/Depth are what a label
-- or an inspector reads, VeinId is what a click sends over the wire.
local function buildVein(
	model: Model,
	origin: CFrame,
	centreZ: number,
	ore: Ore,
	radius: number,
	height: number,
	angleDegrees: number,
	seed: number,
	terrace: number,
	slot: number
)
	local angle = math.rad(angleDegrees)

	local cluster = Instance.new("Model")
	cluster.Name = `Vein_{terrace}_{slot}_{ore.id}`
	cluster:SetAttribute("OreId", ore.id)
	cluster:SetAttribute("Rarity", ore.rarity)
	cluster:SetAttribute("Hardness", ore.hardness)
	cluster:SetAttribute("Value", ore.value)
	cluster:SetAttribute("Depth", ore.depth)
	cluster:SetAttribute("VeinId", OreCatalog.veinId(terrace, slot))

	-- Local +Z points radially outward (CFrame.Angles(0, a, 0) sends +Z to
	-- sin/cos), so -Z is into the pit: that is where the crystals go.
	local base = origin
		* CFrame.new(math.sin(angle) * radius, height, centreZ + math.cos(angle) * radius)
		* CFrame.Angles(0, angle, 0)

	local matrix = part(cluster, "Matrix", {
		Size = Vector3.new(9, 8, 3),
		CFrame = base,
		Color = PALETTE.RockDark,
		Material = Enum.Material.Rock,
	})

	-- An authored mineral model, one per ore id, kept in ReplicatedStorage
	-- next to the Drill -- see drillTemplate's own note on why an authored
	-- asset lives only in the place file and cannot be rebuilt from the
	-- repository. Falls back to the original procedural neon crystal
	-- cluster when no model exists for this ore yet, so a mine is never
	-- missing its veins just because an asset has not been inserted.
	local mineralFolder = if game
		then (game :: any):GetService("ReplicatedStorage"):FindFirstChild("ResearchModels")
		else nil
	local mineralTemplate = mineralFolder and mineralFolder:FindFirstChild(`Ore_{ore.id}`)

	if mineralTemplate and mineralTemplate:IsA("Model") then
		for index = 1, 5 do
			local a = hash(seed, index)
			local b = hash(index, seed + 7)
			local crystal = mineralTemplate:Clone()
			crystal.Name = "Crystal"
			for _, descendant in crystal:GetDescendants() do
				if descendant:IsA("BasePart") then
					descendant.Anchored = true
					descendant.CanCollide = false
				end
			end
			crystal.PrimaryPart = nil
			local scale = 0.55 + a * 0.5
			crystal:PivotTo(
				base
					* CFrame.new((a - 0.5) * 6.4, (b - 0.5) * 5 - index * 0.03, -1.4)
					* CFrame.Angles(a * 6.28, b * 6.28, a * 4)
			)
			crystal:ScaleTo(scale)
			crystal.Parent = cluster
		end
	else
		for index = 1, 5 do
			local a = hash(seed, index)
			local b = hash(index, seed + 7)
			-- The 0.03 per crystal keeps two of them, or a crystal and the
			-- rock behind it, from topping out on the same plane by
			-- coincidence.
			part(cluster, "Crystal", {
				Size = Vector3.new(1.1 + a * 1.4, 1.1 + b * 2.2, 1.1 + a * 1.2),
				CFrame = base
					* CFrame.new((a - 0.5) * 6.4, (b - 0.5) * 5 - index * 0.03, -1.4)
					* CFrame.Angles(a * 2, b * 2, a * 3),
				Color = colourOf(ore),
				Material = Enum.Material.Neon,
				CanCollide = false,
			})
		end
	end

	pointLight(matrix, colourOf(ore), 16, 1.1)
	cluster.Parent = model
end

local function buildResearchPost(model: Model, origin: CFrame, centreZ: number)
	local terrace = TERRACES[1]
	local radius = (terrace.outer + terrace.inner) / 2
	local angle = math.rad(90)
	-- Same convention as a vein: local -Z looks into the pit, so the hut's
	-- open side faces the work.
	local base = origin
		* CFrame.new(math.sin(angle) * radius, terrace.top, centreZ + math.cos(angle) * radius)
		* CFrame.Angles(0, angle, 0)

	part(model, "PostFloor", {
		Size = Vector3.new(18, 1, 16),
		CFrame = base * CFrame.new(0, 0.5 - SEAT, 0),
		Color = PALETTE.Structure,
		Material = Enum.Material.DiamondPlate,
	})
	part(model, "PostWall", {
		Size = Vector3.new(18, 9, 1),
		CFrame = base * CFrame.new(0, 5.4, 7.5),
		Color = PALETTE.Structure,
		Material = Enum.Material.Metal,
	})
	for _, side in { -1, 1 } do
		-- A shade lower than the back wall they meet at the corners.
		part(model, "PostWall", {
			Size = Vector3.new(1, 9, 16),
			CFrame = base * CFrame.new(side * 8.5, 5.37, 0),
			Color = PALETTE.Structure,
			Material = Enum.Material.Metal,
		})
	end
	local roof = part(model, "PostRoof", {
		Size = Vector3.new(20, 1, 18),
		CFrame = base * CFrame.new(0, 10.3, 0),
		Color = PALETTE.Structure,
		Material = Enum.Material.Metal,
	})
	part(model, "PostGlow", {
		Size = Vector3.new(18, 0.4, 0.4),
		CFrame = base * CFrame.new(0, 9.9, -8.6),
		Color = PALETTE.Trim,
		Material = Enum.Material.Neon,
		CanCollide = false,
		CanQuery = false,
	})
	pointLight(roof, PALETTE.Trim, 32, 1.6)
	label(roof, "POSTE DE RECHERCHE", "Analyse des minerais")
end

-- The authored drill, kept in ReplicatedStorage rather than built from code
-- like everything else here. That is a real trade: an authored model lives
-- only in the place file, so this one piece of the mine cannot be rebuilt
-- from the repository the way the rest can. It is deliberate -- a believable
-- drill rig is a lot of parts to write by hand -- and the fallback below
-- keeps the zone whole if the model ever goes missing.
local function drillTemplate(): Model?
	if not game then
		return nil -- Lune: no DataModel, so nothing to clone
	end
	local folder = (game :: any):GetService("ReplicatedStorage"):FindFirstChild("ResearchModels")
	local template = folder and folder:FindFirstChild("Drill")
	if template and template:IsA("Model") then
		return template
	end
	return nil
end

local function buildDrillSite(model: Model, origin: CFrame, centreZ: number)
	local padTop = FLOOR_TOP + 1.1
	local pad = part(model, "DrillSite", {
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(1.2, DRILL_PAD_RADIUS * 2, DRILL_PAD_RADIUS * 2),
		CFrame = origin
			* CFrame.new(0, FLOOR_TOP + 0.6 - SEAT, centreZ)
			* CFrame.Angles(0, 0, math.rad(90)),
		Color = PALETTE.Structure,
		Material = Enum.Material.DiamondPlate,
	})
	pad:SetAttribute("Slot", "Drill")

	local template = drillTemplate()
	local signHeight = 5
	local subtitle = "Emplacement libre"

	if template then
		local drill = template:Clone()
		drill.Name = "Drill"

		-- Seated by its BOUNDING BOX, not by its pivot. An authored model's
		-- pivot sits wherever its author happened to leave it, which is
		-- almost never its base -- pivoting straight onto the pad buries it
		-- or floats it. So: place it, measure where its underside actually
		-- ended up, then correct by the difference.
		drill:PivotTo(origin * CFrame.new(0, 0, centreZ))
		local box, size = drill:GetBoundingBox()
		local target = (origin * CFrame.new(0, padTop, centreZ)).Position.Y
		drill:PivotTo(drill:GetPivot() * CFrame.new(0, target - (box.Position.Y - size.Y / 2), 0))

		drill.ModelStreamingMode = Enum.ModelStreamingMode.Default
		drill.Parent = model

		-- `target` is where the machine's BASE now sits and `size.Y` is its
		-- height, so target + size.Y is its roofline. Derived, not measured:
		-- `box` above was taken BEFORE the seating PivotTo and its centre is
		-- stale by exactly the correction that followed -- reading it here put
		-- the sign 27 studs over the drill instead of 5. Translation does not
		-- change `size`, which is why that half of the reading is still good.
		signHeight = (target + size.Y + 5) - pad.Position.Y
		subtitle = "Inactive"
	else
		-- Nothing standing here: mark the footprint so the spot still reads as
		-- a place something belongs rather than as bare plate.
		for index = 0, 3 do
			local angle = (index / 4) * math.pi * 2 + math.pi / 4
			part(model, "DrillAnchor", {
				Size = Vector3.new(2, 3, 2),
				CFrame = origin * CFrame.new(
					math.sin(angle) * (DRILL_PAD_RADIUS - 1),
					FLOOR_TOP + 1.5 - SEAT,
					centreZ + math.cos(angle) * (DRILL_PAD_RADIUS - 1)
				) * CFrame.Angles(0, angle, 0),
				Color = PALETTE.Trim,
				Material = Enum.Material.Neon,
				CanCollide = false,
			})
		end
	end

	pointLight(pad, PALETTE.Trim, 34, 1.8)
	label(pad, "FOREUSE", subtitle, signHeight)
end

function ResearchMineBuilder.buildZone(parent: Instance, origin: CFrame, span: number): Model
	local half = span / 2
	local centreZ = half + MINE_DISTANCE

	local model = Instance.new("Model")
	model.Name = "ResearchMine"

	buildGangway(model, origin, half, centreZ)
	buildEntrance(model, origin, centreZ)

	for index in TERRACES do
		buildTerrace(model, origin, centreZ, index)
	end

	part(model, "PitFloor", {
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(FLOOR_THICKNESS, FLOOR_RADIUS * 2, FLOOR_RADIUS * 2),
		CFrame = origin
			* CFrame.new(0, FLOOR_TOP - FLOOR_THICKNESS / 2, centreZ)
			* CFrame.Angles(0, 0, math.rad(90)),
		Color = PALETTE.RockDark,
	})

	-- Three flights straight down the -Z side, in line with the gangway: one
	-- unbroken read from the entrance to the drill site. Each lands on the
	-- terrace below it, so the descent has no drop in it. Derived from the
	-- terrace table rather than spelled out: the two used to be six literals
	-- that had to be edited together, which is a step into thin air waiting
	-- to happen the first time a terrace moves.
	for index, terrace in TERRACES do
		local deeper = TERRACES[index + 1]
		local landsOn = if deeper then deeper.top else FLOOR_TOP
		local underside = landsOn - (if deeper then ROCK_THICKNESS else FLOOR_THICKNESS) - 2
		buildStairs(
			model,
			origin,
			centreZ,
			terrace.inner,
			terrace.inner - STAIR_RUNS[index],
			terrace.top - STAIR_RISE,
			landsOn,
			underside,
			STAIR_WIDTHS[index]
		)
	end

	for index, terrace in TERRACES do
		local ores = OreCatalog.atDepth(index)
		if #ores == 0 then
			continue
		end
		for slot, angleDegrees in VEIN_ANGLES do
			buildVein(
				model,
				origin,
				centreZ,
				ores[(slot - 1) % #ores + 1],
				terrace.inner + 1,
				terrace.top - 5,
				angleDegrees,
				index * 10 + slot,
				index,
				slot
			)
		end
	end

	buildResearchPost(model, origin, centreZ)
	buildDrillSite(model, origin, centreZ)

	-- Streams like the ordinary far-away scenery it is. The plot structure
	-- is Persistent because modules would float without it; nothing is
	-- anchored to this from elsewhere, and it sits 300 studs off the deck.
	model.ModelStreamingMode = Enum.ModelStreamingMode.Default
	model.Parent = parent
	return model
end

function ResearchMineBuilder.markUnlocked(handle: PadHandle)
	handle.pad.Color = PALETTE.PadOpen
	local light = handle.pad:FindFirstChildOfClass("PointLight")
	if light then
		light.Color = PALETTE.PadOpen
	end
	local detail = handle.sign:FindFirstChild("Detail")
	if detail and detail:IsA("TextLabel") then
		detail.Text = handle.openText
		detail.TextColor3 = PALETTE.PadOpen
	end
end

-- The only feedback a player who cannot afford it gets. Deliberately not a
-- notification: the answer belongs on the thing that was pressed, and a
-- toast for "nothing happened" is noise on a pad you walk across constantly.
function ResearchMineBuilder.refuse(handle: PadHandle)
	if handle.pad:GetAttribute("Refusing") then
		return
	end
	handle.pad:SetAttribute("Refusing", true)
	handle.pad.Color = PALETTE.PadRefused
	task.delay(0.45, function()
		if handle.pad.Parent then
			handle.pad.Color = PALETTE.PadLocked
			handle.pad:SetAttribute("Refusing", nil)
		end
	end)
end

return ResearchMineBuilder
