--!strict
-- The geometry of every buildable module, built from primitives.
--
-- In code rather than as authored Models in ReplicatedStorage.ModuleModels,
-- for one reason that outweighs the convenience of dragging parts around in
-- Studio: a Model in the place file is the one kind of asset the repository
-- cannot reproduce. Built here, a module's footprint is DERIVED from
-- gridRules.cellSize and the catalogue instead of being eyeballed to match it,
-- so changing the cell size or a module's size rebuilds the art correctly
-- rather than silently misaligning it.
--
-- CONTRACT, same as the authored templates it replaces: built at rotation 0,
-- centred on the origin, base at y = 0, WorldPivot at the origin, and NO
-- PrimaryPart -- StationSceneBuilder pivots the result into place.
--
-- WHAT MAKES THIS NOT LOOK LIKE A PILE OF BOXES
--
-- Five habits, applied to every module, in rough order of how much they buy:
--
--   1. Nothing is a bare box. `rounded` fillets the four vertical edges, which
--      is what actually removes the cube from the silhouette. `chamfered` --
--      the older, cheaper trick -- only steps the top and bottom lines in, so
--      a chamfered box seen from eye level is still a box. Chamfer is now kept
--      for small parts and for the things that SHOULD read as boxes, crates
--      above all; every load-bearing hull is filleted.
--   2. Round where a machine would be round. `dome` caps a cylinder, `barrel`
--      vaults a roof. A hemisphere costs one part and is the cheapest
--      non-cubic shape in the engine.
--   3. Every large face gets recessed seams. A flat hull with panel lines reads
--      as manufactured; the same hull without them reads as untextured.
--   4. Plumbing. `pipeBetween` runs conduit across a plinth or up a tower --
--      the single greeble that most says "this machine is plugged into
--      something".
--   5. Asymmetry. One antenna, one ladder, one offset vent. A mirror-symmetric
--      model reads as a placeholder no matter how much detail is on it.
--
-- PART BUDGET
--
-- Not uniform, on purpose. Corridor and Conduit are the modules a player spams
-- by the dozen, so they stay lean; the 2x2 machines are placed a handful of
-- times each and carry the look, so they get the detail. Measured, at level 1
-- and at level 5:
--
--   Corridor 21 -> 58     SolarPanel/Battery 37 -> 74
--   Conduit  25 -> 62     Smelter 45 -> 82, Fabricator 55 -> 92
--   Core     76 -> 113    CargoBay 54 -> 91
--
-- A fillet costs three parts more than a chamfer, and that is where most of
-- the level-1 figures went. It is spent only on hulls: filleting a 0.3-stud
-- bolt buys a shape nobody can see at four times the price.
--
-- The level-5 column is the one to watch, because it is not hypothetical --
-- a player who tops everything out gets it. A large station of fully upgraded
-- 2x2s lands around 3000-3500 parts, which is still comfortable, and the tier
-- kit is the first thing to trim if it ever stops being.

-- Lives directly under Shared now (moved from Server/Adapters/Roblox so the
-- CLIENT can build the exact same geometry for its build/move ghost preview
-- and BuildPanel's thumbnails -- see CLAUDE.md's module-preview fix notes).
-- Balance is a plain sibling from here, no cross-service boundary to cross.
local Balance = require("./Balance")

local ModuleGeometry = {}

-- The station's presentation palette, shared with StationSceneBuilder's deck
-- so the modules and the hull they sit on cannot drift apart.
ModuleGeometry.Palette = {
	Hull = Color3.fromRGB(182, 190, 205),
	HullShade = Color3.fromRGB(140, 149, 170),
	HullDark = Color3.fromRGB(96, 103, 122),
	Seam = Color3.fromRGB(44, 48, 68),
	Frame = Color3.fromRGB(74, 80, 104),
	Trim = Color3.fromRGB(72, 214, 255),
	Solar = Color3.fromRGB(30, 48, 104),
	SolarCell = Color3.fromRGB(46, 78, 156),
	Thruster = Color3.fromRGB(255, 146, 66),
	Grid = Color3.fromRGB(58, 64, 88),
	Radiator = Color3.fromRGB(228, 232, 240),
	Beacon = Color3.fromRGB(255, 90, 90),
	Hazard = Color3.fromRGB(240, 196, 62),
	Heat = Color3.fromRGB(255, 116, 48),
	Copper = Color3.fromRGB(196, 122, 74),
	Status = Color3.fromRGB(126, 255, 170),
}

local P = ModuleGeometry.Palette

-- Left between a module and its neighbour so two adjacent hulls do not
-- z-fight along their shared face.
local SEAM_GAP = 0.5

-- How tall each module is ALLOWED to build, in studs.
--
-- Deliberately not ModuleCatalog's `height`. That field is a gameplay figure --
-- it is two to eight times smaller than the models it supposedly describes
-- (Core says 4, the model it replaced stood 10.8). Building to it produces a
-- plot of floor tiles: a smelter shorter than the player looking at it. These
-- numbers match the silhouettes of the authored models they replace, so the
-- station keeps the proportions it was laid out with.
--
-- Presentation data, so it lives here rather than in Shared/Balance: nothing on
-- the server or in the domain has any use for it.
local VISUAL_HEIGHT: { [string]: number } = {
	-- Taller than the 10.8 of the model it replaces. The extra 1.7 all goes to
	-- the mast: at 11 the spire was a stub and the beacon sat on the habitat
	-- like a flag, which is the one silhouette the plot's landmark cannot have.
	Core = 12.5,
	Corridor = 1.6,
	Conduit = 3.4,
	SolarPanel = 4,
	Battery = 5.4,
	Radiator = 4.2,
	OreCollector = 8.2,
	Smelter = 9.7,
	Fabricator = 7.3,
	CargoBay = 5.4,
}

-- The parts that make up a module's physical mass. Everything not named here --
-- seams, cables, guy wires, status lights, handrails, bolts -- is decoration a
-- character has to be able to walk through, or it snags on 0.16-stud details it
-- cannot even see.
--
-- One list rather than a flag on each piece, deliberately. A builder that
-- forgets to mark its hull solid produces a machine players fall through, and
-- that is invisible in a screenshot: it only shows up when someone walks into
-- it. One list is one place to review.
--
-- Not covered by the Lune suite -- this is an adapter, and the harness gives
-- Domain and Application no Roblox datatypes on purpose (ARCHITECTURE.md). It
-- was verified in Studio instead, by counting solid parts per module.
local SOLID_PARTS: { [string]: boolean } = {
	-- Shared plinth and walkways
	Skirt = true,
	Deck = true,
	Floor = true,
	Tread = true,
	Kerb = true,
	KerbRail = true,
	-- Core
	Drum = true,
	Collar = true,
	Belt = true,
	Waist = true,
	Habitat = true,
	HabitatDome = true,
	Buttress = true,
	Mast = true,
	-- Conduit
	Leg = true,
	Pipe = true,
	Flange = true,
	-- Solar panel
	Yoke = true,
	Backing = true,
	Bearing = true,
	BearingBall = true,
	-- Battery
	Cell = true,
	CellDome = true,
	Regulator = true,
	-- Radiator
	Fin = true,
	EndCap = true,
	Header = true,
	HeaderCap = true,
	-- Ore collector
	Pedestal = true,
	Column = true,
	Gimbal = true,
	Funnel = true,
	DishBack = true,
	Rim = true,
	Mouth = true,
	Strut = true,
	-- Smelter
	Furnace = true,
	FurnaceVault = true,
	Band = true,
	Chimney = true,
	ChimneyCap = true,
	-- Fabricator
	Shell = true,
	Gantry = true,
	Roof = true,
	Cooler = true,
	Duct = true,
	-- Cargo bay
	Hangar = true,
	Vault = true,
	Door = true,
	Lintel = true,
	Crate = true,
}

ModuleGeometry.SolidParts = SOLID_PARTS

-- The compound primitives name their pieces after the whole: `chamfered` builds
-- Foo, FooCap and FooFoot, `rounded` builds Foo, FooWeb and FooCorner.
-- Collision is decided on the base name so a compound body behaves as the one
-- solid it looks like, rather than as a shell with hollow lids and corners a
-- player walks through.
--
-- Longest suffix first: a `rounded` part called FooCorner must not be read as
-- the base name Foo plus nothing simply because the Cap pattern was tried
-- earlier and failed.
local SOLID_SUFFIXES = { "Corner", "Foot", "Cap", "Web" }

local function solidBase(name: string): string
	for _, suffix in SOLID_SUFFIXES do
		local base = name:match("^(.-)" .. suffix .. "$")
		if base and base ~= "" then
			return base
		end
	end
	return name
end

----------------------------------------------------------------------
-- Primitives

local function piece(model: Model, name: string, props: { [string]: any }): BasePart
	local instance = Instance.new("Part")
	instance.Name = name
	instance.Anchored = true
	instance.CanCollide = false
	instance.CastShadow = false
	instance.TopSurface = Enum.SurfaceType.Smooth
	instance.BottomSurface = Enum.SurfaceType.Smooth
	instance.Material = Enum.Material.Metal
	instance.Color = P.Hull
	for key, value in props do
		(instance :: any)[key] = value
	end
	instance.Parent = model
	return instance
end

-- A Roblox cylinder's circular face is on its X axis, so a standing one has to
-- be rolled a quarter-turn. Wrapped here because getting it wrong produces a
-- barrel lying on its side, which is easy to miss in a screenshot.
local function upright(
	model: Model,
	name: string,
	diameter: number,
	height: number,
	at: CFrame,
	props: { [string]: any }?
): BasePart
	local merged: { [string]: any } = {
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(height, diameter, diameter),
		CFrame = at * CFrame.Angles(0, 0, math.rad(90)),
	}
	for key, value in props or {} do
		merged[key] = value
	end
	return piece(model, name, merged)
end

local function glow(
	model: Model,
	name: string,
	size: Vector3,
	at: CFrame,
	colour: Color3?
): BasePart
	return piece(model, name, {
		Size = size,
		CFrame = at,
		Color = colour or P.Trim,
		Material = Enum.Material.Neon,
		CanQuery = false,
	})
end

-- Kept short and dim on purpose. A PointLight with the range these modules sit
-- at floods its neighbours and tints the whole plot: an early pass gave the
-- core a pink hull and the smelter an orange one. The neon part already reads
-- as the light source -- the PointLight only has to seat it in the scene.
local function lamp(host: BasePart, colour: Color3)
	local light = Instance.new("PointLight")
	light.Color = colour
	light.Range = 8
	light.Brightness = 0.6
	light.Parent = host
end

----------------------------------------------------------------------
-- Detailing
--
-- These are what the modules are actually made of. A builder below should read
-- as a description of a machine, not as a list of Vector3s.

-- A box whose top and bottom edges step inward. Three parts, and the single
-- most effective thing here: the eye reads a chamfer as a machined edge and a
-- sharp one as an untouched primitive.
local function chamfered(
	model: Model,
	name: string,
	size: Vector3,
	at: CFrame,
	props: { [string]: any }?
): ()
	local bevel = math.min(0.45, size.X * 0.07, size.Z * 0.07, size.Y * 0.2)

	local function spawn(suffix: string, partSize: Vector3, offsetY: number)
		local merged: { [string]: any } =
			{ Size = partSize, CFrame = at * CFrame.new(0, offsetY, 0) }
		for key, value in props or {} do
			merged[key] = value
		end
		piece(model, name .. suffix, merged)
	end

	spawn("", Vector3.new(size.X, size.Y - bevel * 2, size.Z), 0)
	spawn("Cap", Vector3.new(size.X - bevel * 2, bevel, size.Z - bevel * 2), size.Y / 2 - bevel / 2)
	spawn(
		"Foot",
		Vector3.new(size.X - bevel * 2, bevel, size.Z - bevel * 2),
		-size.Y / 2 + bevel / 2
	)
end

-- A box whose four VERTICAL edges are rounded off: two crossing slabs, plus a
-- cylinder standing in each corner. Six parts against `chamfered`'s three, and
-- the reason to pay it is that a chamfer works on the top and bottom lines
-- only -- from a player's eye height, which is where a module is actually
-- looked at, a chamfered hull still has four hard vertical corners and still
-- reads as a cube. The fillet is the one change that removes it.
--
-- The radius is a fraction of the smaller span rather than a constant, so a
-- squat 8-stud furnace and a slim 2-stud strut both come out looking machined
-- instead of one looking melted. Capped absolutely as well: past about a stud
-- the corners start eating the face the seams and vents have to sit on.
local function rounded(
	model: Model,
	name: string,
	size: Vector3,
	at: CFrame,
	props: { [string]: any }?
): ()
	local radius = math.min(1, size.X * 0.2, size.Z * 0.2)

	local function merge(extra: { [string]: any }): { [string]: any }
		local merged: { [string]: any } = table.clone(props or {})
		for key, value in extra do
			merged[key] = value
		end
		return merged
	end

	-- The cross. Neither slab reaches a corner; the cylinders do.
	piece(
		model,
		name,
		merge({
			Size = Vector3.new(size.X - radius * 2, size.Y, size.Z),
			CFrame = at,
		})
	)
	piece(
		model,
		name .. "Web",
		merge({
			Size = Vector3.new(size.X, size.Y, size.Z - radius * 2),
			CFrame = at,
		})
	)

	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			upright(
				model,
				name .. "Corner",
				radius * 2,
				size.Y,
				at * CFrame.new(sx * (size.X / 2 - radius), 0, sz * (size.Z / 2 - radius)),
				props
			)
		end
	end
end

-- A hemisphere sitting on `at`, for capping a cylinder or crowning a hull.
--
-- Roblox renders a Ball at the diameter of its SMALLEST axis, so there is no
-- such thing as a squashed one: a shallower dome is made by SINKING the sphere
-- into whatever it caps, never by scaling it. Passing a rise above half the
-- diameter would lift the sphere clear of its host and leave it floating, so
-- it is clamped rather than trusted.
local function dome(
	model: Model,
	name: string,
	diameter: number,
	rise: number,
	at: CFrame,
	props: { [string]: any }?
): BasePart
	local merged: { [string]: any } = {
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(diameter, diameter, diameter),
		CFrame = at * CFrame.new(0, math.min(rise, diameter / 2) - diameter / 2, 0),
	}
	for key, value in props or {} do
		merged[key] = value
	end
	return piece(model, name, merged)
end

-- A cylinder lying on its side along the model's X axis -- a vault, a tank, a
-- rolled roof. A Roblox cylinder's circular face is already on X, so unlike
-- `upright` this one needs no correcting turn; it exists to say what the shape
-- IS at the call site, and because a raw Vector3.new(length, d, d) reads as a
-- typo next to every other Size in this file.
local function barrel(
	model: Model,
	name: string,
	length: number,
	diameter: number,
	at: CFrame,
	props: { [string]: any }?
): BasePart
	local merged: { [string]: any } = {
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(length, diameter, diameter),
		CFrame = at,
	}
	for key, value in props or {} do
		merged[key] = value
	end
	return piece(model, name, merged)
end

-- Recessed seams across a face. `face` sits ON the surface with +Z pointing
-- out of it; local X runs across the width.
local function faceSeams(
	model: Model,
	face: CFrame,
	width: number,
	height: number,
	count: number
): ()
	for index = 1, count do
		local t = index / (count + 1)
		piece(model, "Seam", {
			Size = Vector3.new(0.16, height, 0.14),
			CFrame = face * CFrame.new((t - 0.5) * width, 0, 0.03),
			Color = P.Seam,
			CanQuery = false,
		})
	end
end

-- A cylinder running between two points, in the model's own space. Reads as
-- plumbing, which is most of what separates a machine from a crate.
local function pipeBetween(
	model: Model,
	name: string,
	from: Vector3,
	to: Vector3,
	diameter: number,
	colour: Color3?
): BasePart
	local delta = to - from
	-- lookAt puts the LookVector (local -Z) on the target; the extra quarter-turn
	-- swings the cylinder's own X axis onto it.
	return piece(model, name, {
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(delta.Magnitude, diameter, diameter),
		CFrame = CFrame.lookAt(from + delta / 2, to) * CFrame.Angles(0, math.rad(90), 0),
		Color = colour or P.HullDark,
		CanQuery = false,
	})
end

-- Small coloured indicators. Two grey machines with different status colours
-- are still telling each other apart at fifty studs.
local function statusRow(model: Model, at: CFrame, count: number, colour: Color3): ()
	for index = 1, count do
		glow(
			model,
			"Status",
			Vector3.new(0.24, 0.24, 0.16),
			at * CFrame.new((index - (count + 1) / 2) * 0.5, 0, 0),
			if index == count then P.Hazard else colour
		)
	end
end

-- Posts and a top rail along a run. Handrails are the detail players read as
-- "a person works here", and they cost four parts.
local function railing(model: Model, from: Vector3, to: Vector3, height: number, posts: number): ()
	for index = 0, posts - 1 do
		local t = if posts == 1 then 0.5 else index / (posts - 1)
		local at = from:Lerp(to, t)
		piece(model, "Post", {
			Size = Vector3.new(0.2, height, 0.2),
			CFrame = CFrame.new(at + Vector3.new(0, height / 2, 0)),
			Color = P.Frame,
			CanQuery = false,
		})
	end
	local lift = Vector3.new(0, height, 0)
	pipeBetween(model, "Rail", from + lift, to + lift, 0.22, P.Frame)
end

-- Rungs between two rails. Asymmetric by construction -- it goes on one face
-- only, which is exactly the point.
local function ladder(model: Model, at: CFrame, height: number): ()
	for _, side in { -0.4, 0.4 } do
		piece(model, "LadderRail", {
			Size = Vector3.new(0.16, height, 0.16),
			CFrame = at * CFrame.new(side, height / 2, 0),
			Color = P.Frame,
			CanQuery = false,
		})
	end
	local rungs = math.max(2, math.floor(height / 0.8))
	for index = 1, rungs do
		piece(model, "Rung", {
			Size = Vector3.new(0.9, 0.12, 0.12),
			CFrame = at * CFrame.new(0, index * height / (rungs + 1), 0),
			Color = P.HullShade,
			CanQuery = false,
		})
	end
end

-- The plinth every module stands on: a dark skirt, a lighter deck plate, and a
-- service pipe running one edge. The shared vocabulary that makes ten different
-- machines read as one station.
local function plinth(model: Model, spanX: number, spanZ: number): number
	piece(model, "Skirt", {
		Size = Vector3.new(spanX, 0.5, spanZ),
		CFrame = CFrame.new(0, 0.25, 0),
		Color = P.Seam,
		Material = Enum.Material.DiamondPlate,
	})

	piece(model, "Deck", {
		Size = Vector3.new(spanX - 0.9, 0.3, spanZ - 0.9),
		CFrame = CFrame.new(0, 0.6, 0),
		Color = P.HullShade,
		Material = Enum.Material.DiamondPlate,
	})

	-- Offset to one side rather than centred: the asymmetry is free here.
	local run = spanX / 2 - 1
	pipeBetween(
		model,
		"Service",
		Vector3.new(-run, 0.45, spanZ * 0.36),
		Vector3.new(run, 0.45, spanZ * 0.36),
		0.3,
		P.Copper
	)

	for _, sx in { -1, 1 } do
		piece(model, "Clamp", {
			Size = Vector3.new(0.35, 0.5, 0.7),
			CFrame = CFrame.new(sx * run * 0.6, 0.5, spanZ * 0.36),
			Color = P.Frame,
			CanQuery = false,
		})
	end

	return 0.75
end

-- Bolts at the four corners.
local function corners(model: Model, spanX: number, spanZ: number, y: number, inset: number)
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			upright(
				model,
				"Bolt",
				0.55,
				0.35,
				CFrame.new(sx * (spanX / 2 - inset), y, sz * (spanZ / 2 - inset)),
				{ Color = P.Frame }
			)
		end
	end
end

----------------------------------------------------------------------
-- The builders

type Builder = (model: Model, spanX: number, spanZ: number, height: number) -> ()

local BUILDERS: { [string]: Builder } = {}

-- Structure -----------------------------------------------------------

-- The core: a tiered tower. The only unique module and the tallest thing on
-- the plot, so it is what a player orients themselves by -- which is why it
-- gets the antenna, the beacon and the ladder rather than a taller box.
BUILDERS.Core = function(model, spanX, spanZ, height)
	local base = plinth(model, spanX, spanZ)
	local drum = height * 0.35

	upright(
		model,
		"Drum",
		spanX * 0.64,
		drum,
		CFrame.new(0, base + drum / 2, 0),
		{ Color = P.Hull }
	)
	upright(model, "Collar", spanX * 0.76, 0.8, CFrame.new(0, base + 0.4, 0), { Color = P.Frame })
	upright(model, "Belt", spanX * 0.7, 0.5, CFrame.new(0, base + drum * 0.45, 0), {
		Color = P.HullDark,
	})

	-- Ribs around the drum, so a cylinder does not read as a can.
	for index = 0, 7 do
		local angle = math.rad(index * 45)
		piece(model, "Rib", {
			Size = Vector3.new(0.3, drum * 0.85, 0.5),
			CFrame = CFrame.new(0, base + drum / 2, 0)
				* CFrame.Angles(0, angle, 0)
				* CFrame.new(0, 0, spanZ * 0.32),
			Color = P.HullShade,
			CanQuery = false,
		})
	end

	upright(model, "Ring", spanX * 0.7, 0.45, CFrame.new(0, base + drum * 0.82, 0), {
		Color = P.Trim,
		Material = Enum.Material.Neon,
		CanQuery = false,
	})

	local waist = height * 0.15
	upright(model, "Waist", spanX * 0.36, waist, CFrame.new(0, base + drum + waist / 2, 0), {
		Color = P.Frame,
	})
	-- Risers run straight up OUTSIDE the waist rather than splaying between two
	-- radii: three vertical lines read as a service cage, three diagonal ones
	-- read as sticks poking out of the model.
	for index = 0, 2 do
		local angle = math.rad(index * 120)
		local radiusX, radiusZ = spanX * 0.26, spanZ * 0.26
		pipeBetween(
			model,
			"Riser",
			Vector3.new(math.cos(angle) * radiusX, base + drum, math.sin(angle) * radiusZ),
			Vector3.new(math.cos(angle) * radiusX, base + drum + waist, math.sin(angle) * radiusZ),
			0.28,
			P.Copper
		)
	end

	local habitat = height * 0.16
	local habitatY = base + drum + waist + habitat / 2
	upright(model, "Habitat", spanX * 0.58, habitat, CFrame.new(0, habitatY, 0), {
		Color = P.HullShade,
	})
	upright(model, "HabitatLip", spanX * 0.64, 0.3, CFrame.new(0, habitatY - habitat / 2, 0), {
		Color = P.Frame,
	})
	-- The tower's roof is a dome rather than a flat lid. This is the highest
	-- thing on the plot short of the mast, so it is the one silhouette every
	-- player sees from every angle -- a disc there reads as an unfinished
	-- cylinder no matter how detailed the rest of the model is.
	dome(
		model,
		"HabitatDome",
		spanX * 0.58,
		spanX * 0.2,
		CFrame.new(0, habitatY + habitat / 2, 0),
		{ Color = P.Hull }
	)

	for index = 0, 5 do
		local angle = math.rad(index * 60)
		glow(
			model,
			"Window",
			Vector3.new(1.3, habitat * 0.36, 0.3),
			CFrame.new(0, habitatY, 0) * CFrame.Angles(0, angle, 0) * CFrame.new(0, 0, spanZ * 0.29)
		)
	end

	ladder(model, CFrame.new(0, base, spanZ * 0.34), drum)

	local mastBase = base + drum + waist + habitat
	upright(
		model,
		"Mast",
		0.6,
		height - mastBase - 0.5,
		CFrame.new(0, (mastBase + height - 0.5) / 2, 0),
		{ Color = P.Frame }
	)
	-- Guy wires: three thin lines are what turn a pole into a mast.
	for index = 0, 2 do
		local angle = math.rad(30 + index * 120)
		pipeBetween(
			model,
			"Guy",
			Vector3.new(0, height - 1.2, 0),
			Vector3.new(math.cos(angle) * spanX * 0.26, mastBase, math.sin(angle) * spanZ * 0.26),
			0.12,
			P.HullDark
		)
	end

	-- Cross spars up the mast. A bare pole is a pole; a pole with spars is an
	-- antenna, and that is the whole job of the top of this model.
	for _, spar in { { at = 0.45, span = 2.6 }, { at = 0.75, span = 1.7 } } do
		local y = mastBase + (height - 0.5 - mastBase) * spar.at
		piece(model, "Spar", {
			Size = Vector3.new(spar.span, 0.16, 0.16),
			CFrame = CFrame.new(0, y, 0) * CFrame.Angles(0, math.rad(30), 0),
			Color = P.HullDark,
			CanQuery = false,
		})
		for _, sx in { -1, 1 } do
			piece(model, "SparTip", {
				Size = Vector3.new(0.14, 0.5, 0.14),
				CFrame = CFrame.new(0, y + 0.25, 0)
					* CFrame.Angles(0, math.rad(30), 0)
					* CFrame.new(sx * spar.span / 2, 0, 0),
				Color = P.HullDark,
				CanQuery = false,
			})
		end
	end

	local beacon = upright(model, "Beacon", 0.8, 0.9, CFrame.new(0, height - 0.35, 0), {
		Color = P.Beacon,
		Material = Enum.Material.Neon,
		CanQuery = false,
	})
	lamp(beacon, P.Beacon)

	-- Buttresses take the tower back down to the footprint, so it does not look
	-- balanced on a pin.
	for index = 0, 3 do
		local angle = math.rad(45 + index * 90)
		rounded(
			model,
			"Buttress",
			Vector3.new(1.3, drum * 0.9, 1.3),
			CFrame.new(
				math.cos(angle) * spanX * 0.36,
				base + drum * 0.45,
				math.sin(angle) * spanZ * 0.36
			) * CFrame.Angles(0, -angle, 0),
			{ Color = P.Frame }
		)
	end

	statusRow(model, CFrame.new(0, base + drum * 0.2, spanZ * 0.47), 4, P.Status)
end

-- The corridor: walkable deck, nothing more. It carries no resource, so it
-- gets no lit conduit -- the silhouette has to say "you can walk here, but
-- nothing flows". Kept lean: this is the module players place by the dozen.
BUILDERS.Corridor = function(model, spanX, spanZ, height)
	-- The fillet goes on the FLOOR and not on the tread above it: the floor is
	-- the outline, the tread is inset and its corners are hidden by the kerbs.
	-- Rounding the part nobody can see would be the five parts this module can
	-- least afford.
	rounded(
		model,
		"Floor",
		Vector3.new(spanX, height * 0.45, spanZ),
		CFrame.new(0, height * 0.225, 0),
		{
			Color = P.Seam,
			Material = Enum.Material.DiamondPlate,
		}
	)

	piece(model, "Tread", {
		Size = Vector3.new(spanX - 1.6, height * 0.3, spanZ - 1.6),
		CFrame = CFrame.new(0, height * 0.56, 0),
		Color = P.HullShade,
		Material = Enum.Material.DiamondPlate,
	})

	-- Grating: four slats across the tread. Enough to break the flat plate,
	-- cheap enough to place fifty of these.
	for index = 1, 4 do
		piece(model, "Slat", {
			Size = Vector3.new(spanX - 2.2, 0.1, 0.3),
			CFrame = CFrame.new(0, height * 0.72, (index - 2.5) * (spanZ - 2.4) / 4),
			Color = P.HullDark,
			CanQuery = false,
		})
	end

	for _, sz in { -1, 1 } do
		piece(model, "Kerb", {
			Size = Vector3.new(spanX, height * 0.85, 0.8),
			CFrame = CFrame.new(0, height * 0.425, sz * (spanZ / 2 - 0.4)),
			Color = P.Frame,
		})
		-- A capsule laid along the top of each kerb. One part, and it turns the
		-- square profile of a walkway edge into a handrail -- the cheapest
		-- rounding in the file, on the module that has the least to spend.
		barrel(
			model,
			"KerbRail",
			spanX,
			0.5,
			CFrame.new(0, height * 0.85, sz * (spanZ / 2 - 0.4)),
			{ Color = P.HullShade }
		)
		glow(
			model,
			"EdgeLight",
			Vector3.new(spanX - 2.4, 0.16, 0.26),
			CFrame.new(0, height * 0.8, sz * (spanZ / 2 - 1))
		)
	end

	corners(model, spanX, spanZ, height * 0.85, 1.2)
end

-- Logistics -----------------------------------------------------------

-- The conduit: a pipe raised on legs. This is the module that makes a network
-- legible from the air, so the lit band along it is the whole point, and the
-- clearance under it is what tells it apart from a corridor at a glance.
-- Also kept lean -- a network is made of many of these.
BUILDERS.Conduit = function(model, spanX, spanZ, height)
	local base = plinth(model, spanX, spanZ)
	local axis = height * 0.6
	local bore = height - axis

	for _, sx in { -1, 1 } do
		rounded(
			model,
			"Leg",
			Vector3.new(1.1, axis - base, 1.7),
			CFrame.new(sx * spanX * 0.28, base + (axis - base) / 2, 0),
			{ Color = P.Frame }
		)
	end

	-- Laid along X so that a run of conduits meets end to end.
	piece(model, "Pipe", {
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(spanX, bore, bore),
		CFrame = CFrame.new(0, axis + bore / 2, 0),
		Color = P.Hull,
	})

	for _, sx in { -1, 1 } do
		piece(model, "Flange", {
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.7, bore * 1.24, bore * 1.24),
			CFrame = CFrame.new(sx * (spanX / 2 - 0.35), axis + bore / 2, 0),
			Color = P.Frame,
		})
	end

	-- A second, thinner line clipped to the main bore. Two pipes read as a
	-- system; one reads as a tube.
	pipeBetween(
		model,
		"Bypass",
		Vector3.new(-spanX / 2, axis + bore * 0.2, spanZ * 0.22),
		Vector3.new(spanX / 2, axis + bore * 0.2, spanZ * 0.22),
		0.32,
		P.Copper
	)

	glow(model, "Flow", Vector3.new(spanX - 1.8, 0.22, 0.6), CFrame.new(0, height - 0.15, 0))

	upright(model, "Valve", 1.1, 0.4, CFrame.new(spanX * 0.16, height + 0.1, 0), {
		Color = P.Thruster,
	})
	upright(model, "Handwheel", 1.5, 0.16, CFrame.new(spanX * 0.16, height + 0.35, 0), {
		Color = P.HullDark,
	})
	dome(
		model,
		"ValveCrown",
		0.7,
		0.35,
		CFrame.new(spanX * 0.16, height + 0.43, 0),
		{ Color = P.Thruster }
	)
end

-- Energy --------------------------------------------------------------

-- The solar panel: a tilted array on a mast. The tilt is what makes it
-- readable in one glance -- flat on the deck it was indistinguishable from the
-- radiator next to it, and it also earns the module its "nothing at all in the
-- shade" rule visually.
BUILDERS.SolarPanel = function(model, spanX, spanZ, height)
	local base = plinth(model, spanX, spanZ)

	upright(model, "Mast", 1.2, height * 0.45, CFrame.new(0, base + height * 0.22, 0), {
		Color = P.Frame,
	})
	upright(model, "Bearing", 1.7, 0.35, CFrame.new(0, base + height * 0.42, 0), {
		Color = P.HullDark,
	})
	-- A ball joint at the pivot, which is what the tilt of the array implies is
	-- there. It also stops the mast reading as a pole with a plank on it.
	dome(model, "BearingBall", 1.5, 0.75, CFrame.new(0, base + height * 0.42, 0), {
		Color = P.HullShade,
	})

	rounded(
		model,
		"Yoke",
		Vector3.new(spanX * 0.5, 0.5, 0.8),
		CFrame.new(0, base + height * 0.45, 0),
		{ Color = P.HullShade }
	)

	local tilt = CFrame.new(0, height * 0.72, 0) * CFrame.Angles(math.rad(-28), 0, 0)

	-- The array keeps a flat face -- a solar panel that bulges is a solar panel
	-- nobody recognises -- but its four corners come off. That is enough to
	-- stop the silhouette being a rectangle floating over a plot.
	rounded(model, "Backing", Vector3.new(spanX - 1, 0.3, spanZ - 1), tilt, { Color = P.Frame })

	-- Truss under the array. Without it the panel floats off its yoke.
	for _, sx in { -1, 1 } do
		pipeBetween(
			model,
			"Brace",
			(tilt * CFrame.new(sx * spanX * 0.3, -0.2, 0)).Position,
			Vector3.new(sx * spanX * 0.16, base + height * 0.4, 0),
			0.24,
			P.HullDark
		)
	end

	local columns, rows = 4, 2
	local cellX = (spanX - 2) / columns
	local cellZ = (spanZ - 2) / rows

	for ix = 0, columns - 1 do
		for iz = 0, rows - 1 do
			piece(model, "Cell", {
				Size = Vector3.new(cellX - 0.35, 0.22, cellZ - 0.35),
				CFrame = tilt * CFrame.new(
					(ix - (columns - 1) / 2) * cellX,
					0.28,
					(iz - (rows - 1) / 2) * cellZ
				),
				-- Alternating shades fake the sheen a flat plate cannot have.
				Color = if (ix + iz) % 2 == 0 then P.Solar else P.SolarCell,
				Material = Enum.Material.Glass,
				Reflectance = 0.35,
			})
		end
	end

	-- Busbars between the cell columns.
	for index = 1, columns - 1 do
		piece(model, "Busbar", {
			Size = Vector3.new(0.18, 0.26, spanZ - 1.4),
			CFrame = tilt * CFrame.new((index - columns / 2) * cellX, 0.3, 0),
			Color = P.HullShade,
			CanQuery = false,
		})
	end

	glow(
		model,
		"Edge",
		Vector3.new(spanX - 1.4, 0.16, 0.26),
		tilt * CFrame.new(0, 0.3, spanZ * 0.42)
	)
	statusRow(model, CFrame.new(spanX * 0.3, base + 0.5, spanZ * 0.42), 3, P.Status)
end

-- The battery: a bank of standing cells with a charge column. Cylinders, so it
-- cannot be confused with the panel or the radiator around it.
BUILDERS.Battery = function(model, spanX, spanZ, height)
	local base = plinth(model, spanX, spanZ)
	local cell = height - base - 0.9

	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			local x, z = sx * spanX * 0.2, sz * spanZ * 0.2
			upright(model, "Cell", spanX * 0.3, cell, CFrame.new(x, base + cell / 2, z), {
				Color = P.Hull,
			})
			-- Two bands per cell: a plain cylinder is the most primitive-looking
			-- shape there is.
			for _, fraction in { 0.3, 0.72 } do
				upright(
					model,
					"Band",
					spanX * 0.33,
					0.28,
					CFrame.new(x, base + cell * fraction, z),
					{ Color = P.HullDark }
				)
			end
			-- Pressure vessels have domed ends, and these cells now read as
			-- pressure vessels instead of as tins. The terminal is kept on top
			-- of the dome rather than replaced by it: it is the part the bus
			-- bars connect to, and a bus running into a bare curve looks
			-- unattached.
			dome(model, "CellDome", spanX * 0.3, spanX * 0.12, CFrame.new(x, base + cell, z), {
				Color = P.Hull,
			})
			upright(
				model,
				"Terminal",
				spanX * 0.17,
				0.45,
				CFrame.new(x, base + cell + spanX * 0.1, z),
				{
					Color = P.Thruster,
				}
			)
		end
	end

	-- Bus bars joining the four terminals into one bank. Lifted with the
	-- terminals so they still meet them now the cells are domed.
	for _, sz in { -1, 1 } do
		pipeBetween(
			model,
			"Bus",
			Vector3.new(-spanX * 0.2, base + cell + spanX * 0.1 + 0.3, sz * spanZ * 0.2),
			Vector3.new(spanX * 0.2, base + cell + spanX * 0.1 + 0.3, sz * spanZ * 0.2),
			0.26,
			P.Copper
		)
	end

	rounded(
		model,
		"Regulator",
		Vector3.new(spanX * 0.3, cell * 0.45, spanZ * 0.22),
		CFrame.new(0, base + cell * 0.28, 0),
		{ Color = P.Frame }
	)
	glow(
		model,
		"Charge",
		Vector3.new(0.35, cell * 0.34, 0.35),
		CFrame.new(0, base + cell * 0.28, spanZ * 0.13)
	)
	statusRow(model, CFrame.new(0, base + cell * 0.55, spanZ * 0.12), 3, P.Status)
end

-- Thermal -------------------------------------------------------------

-- The radiator: upright white fins with heat bleeding between them. It has to
-- look like it wants open space around it, since that is exactly what the rule
-- behind it checks.
BUILDERS.Radiator = function(model, spanX, spanZ, height)
	local base = plinth(model, spanX, spanZ)
	local fins = 7
	local pitch = (spanX - 1.6) / fins
	local finHeight = height - base - 0.4

	-- The header the fins hang off. Fins standing on nothing look unfinished.
	pipeBetween(
		model,
		"Header",
		Vector3.new(-spanX / 2 + 0.6, base + 0.4, 0),
		Vector3.new(spanX / 2 - 0.6, base + 0.4, 0),
		0.7,
		P.HullDark
	)

	for index = 0, fins - 1 do
		local offset = (index - (fins - 1) / 2) * pitch
		piece(model, "Fin", {
			Size = Vector3.new(pitch * 0.42, finHeight, spanZ - 1.6),
			CFrame = CFrame.new(offset, base + 0.3 + finHeight / 2, 0),
			Color = P.Radiator,
			Material = Enum.Material.SmoothPlastic,
		})
		-- Each fin gets a dark spine, which stops seven white slabs from
		-- flattening into one white slab at distance.
		piece(model, "Spine", {
			Size = Vector3.new(pitch * 0.46, 0.22, spanZ - 1.2),
			CFrame = CFrame.new(offset, base + 0.3 + finHeight * 0.72, 0),
			Color = P.HullDark,
			CanQuery = false,
		})
		if index < fins - 1 then
			glow(
				model,
				"Vent",
				Vector3.new(pitch * 0.26, finHeight * 0.55, 0.35),
				CFrame.new(offset + pitch / 2, base + 0.3 + finHeight * 0.38, 0),
				P.Heat
			)
		end
	end

	for _, sx in { -1, 1 } do
		rounded(
			model,
			"EndCap",
			Vector3.new(0.8, finHeight * 0.5, spanZ - 0.9),
			CFrame.new(sx * (spanX / 2 - 0.4), base + 0.3 + finHeight * 0.25, 0),
			{ Color = P.HullShade }
		)
		-- The header is a pipe, and a pipe that stops dead at a flat face reads
		-- as cut off. One hemisphere per end closes it.
		dome(model, "HeaderCap", 0.7, 0.35, CFrame.new(sx * (spanX / 2 - 0.6), base + 0.4, 0), {
			Color = P.HullDark,
		})
	end

	statusRow(model, CFrame.new(spanX * 0.34, base + 0.55, spanZ * 0.42), 3, P.Heat)
end

-- Production ----------------------------------------------------------

-- The ore collector: an intake dish on a column, tipped off the vertical so it
-- reads as aimed at something rather than as a bowl left on a table.
BUILDERS.OreCollector = function(model, spanX, spanZ, height)
	local base = plinth(model, spanX, spanZ)
	local column = height * 0.44

	rounded(
		model,
		"Pedestal",
		Vector3.new(spanX * 0.34, column * 0.35, spanZ * 0.34),
		CFrame.new(0, base + column * 0.17, 0),
		{ Color = P.HullShade }
	)
	upright(model, "Column", spanX * 0.22, column, CFrame.new(0, base + column / 2, 0), {
		Color = P.Frame,
	})
	upright(model, "Gimbal", spanX * 0.34, 0.6, CFrame.new(0, base + column, 0), {
		Color = P.HullDark,
	})

	local dish = CFrame.new(0, base + column + height * 0.16, 0)
		* CFrame.Angles(math.rad(-22), 0, 0)

	-- The hub on the back of the dish. This is the module a player most often
	-- walks BEHIND -- it sits at the edge of the plot aiming outward -- and a
	-- receiver seen from behind is a boss with a curve on it, not a flat disc.
	--
	-- Sized well under the funnel it sits on, and not at all for the reason it
	-- looks: `dome` is a whole sphere with its lower half meant to be buried,
	-- so a bulge as WIDE as the dish is a sphere as DEEP as the dish, and this
	-- one is tipped back 22 degrees and flipped. At 0.76 of the span it swung
	-- 0.85 studs below the module's base plane -- through the deck, and past
	-- the y = 0 contract the scene builder pivots against.
	dome(
		model,
		"DishBack",
		spanX * 0.45,
		spanX * 0.16,
		dish * CFrame.Angles(math.rad(180), 0, 0),
		{ Color = P.HullShade }
	)

	-- A cone would need a mesh. A shallow drum with a darker mouth sunk into it
	-- reads as a funnel from every angle a player sees it from.
	piece(model, "Funnel", {
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(height * 0.2, spanX * 0.78, spanX * 0.78),
		CFrame = dish * CFrame.Angles(0, 0, math.rad(90)),
		Color = P.Hull,
	})
	piece(model, "Rim", {
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.4, spanX * 0.84, spanX * 0.84),
		CFrame = dish * CFrame.new(0, height * 0.09, 0) * CFrame.Angles(0, 0, math.rad(90)),
		Color = P.Frame,
	})
	piece(model, "Mouth", {
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(height * 0.1, spanX * 0.62, spanX * 0.62),
		CFrame = dish * CFrame.new(0, height * 0.08, 0) * CFrame.Angles(0, 0, math.rad(90)),
		Color = P.Seam,
		Material = Enum.Material.DiamondPlate,
	})

	-- Feed arms reaching over the mouth, like a real receiver's.
	for index = 0, 2 do
		local angle = math.rad(index * 120)
		pipeBetween(
			model,
			"FeedArm",
			(dish * CFrame.new(
				math.cos(angle) * spanX * 0.34,
				height * 0.09,
				math.sin(angle) * spanX * 0.34
			)).Position,
			(dish * CFrame.new(0, height * 0.26, 0)).Position,
			0.22,
			P.HullDark
		)
	end

	local intake = piece(model, "Intake", {
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.5, spanX * 0.24, spanX * 0.24),
		CFrame = dish * CFrame.new(0, height * 0.27, 0) * CFrame.Angles(0, 0, math.rad(90)),
		Color = P.Thruster,
		Material = Enum.Material.Neon,
		CanQuery = false,
	})
	lamp(intake, P.Thruster)

	for index = 0, 2 do
		local angle = math.rad(index * 120)
		rounded(
			model,
			"Strut",
			Vector3.new(0.9, column * 0.9, 0.9),
			CFrame.new(
				math.cos(angle) * spanX * 0.28,
				base + column * 0.45,
				math.sin(angle) * spanZ * 0.28
			) * CFrame.Angles(math.rad(10), -angle, 0),
			{ Color = P.Frame }
		)
	end

	statusRow(model, CFrame.new(spanX * 0.2, base + column * 0.3, spanZ * 0.18), 3, P.Status)
end

-- The smelter: the heat source, and the tallest production module. The chimney
-- is what says so from the other side of the plot.
BUILDERS.Smelter = function(model, spanX, spanZ, height)
	local base = plinth(model, spanX, spanZ)
	local body = height * 0.48

	rounded(
		model,
		"Furnace",
		Vector3.new(spanX * 0.8, body, spanZ * 0.8),
		CFrame.new(0, base + body / 2, 0),
		{ Color = P.Hull }
	)
	-- A furnace is a vessel, so it gets a rolled top instead of a lid. The
	-- vault runs along X, which is the axis the ore feed and the chimney are
	-- already offset along -- rolling it the other way would fight them.
	barrel(
		model,
		"FurnaceVault",
		spanX * 0.8,
		spanZ * 0.5,
		CFrame.new(0, base + body, 0),
		{ Color = P.Hull }
	)
	faceSeams(model, CFrame.new(0, base + body * 0.5, spanZ * 0.4), spanX * 0.72, body * 0.8, 3)
	faceSeams(
		model,
		CFrame.new(0, base + body * 0.5, -spanZ * 0.4) * CFrame.Angles(0, math.rad(180), 0),
		spanX * 0.72,
		body * 0.8,
		3
	)

	piece(model, "Band", {
		Size = Vector3.new(spanX * 0.84, 0.5, spanZ * 0.84),
		CFrame = CFrame.new(0, base + body * 0.72, 0),
		Color = P.Frame,
	})

	for _, sx in { -1, 1 } do
		glow(
			model,
			"Vent",
			Vector3.new(0.35, body * 0.45, spanZ * 0.5),
			CFrame.new(sx * spanX * 0.4, base + body * 0.38, 0),
			P.Heat
		)
	end

	local door = piece(model, "Door", {
		Size = Vector3.new(spanX * 0.34, body * 0.42, 0.45),
		CFrame = CFrame.new(0, base + body * 0.3, spanZ * 0.4),
		Color = P.Heat,
		Material = Enum.Material.Neon,
		CanQuery = false,
	})
	lamp(door, P.Heat)
	piece(model, "DoorFrame", {
		Size = Vector3.new(spanX * 0.42, body * 0.5, 0.3),
		CFrame = CFrame.new(0, base + body * 0.3, spanZ * 0.39),
		Color = P.Frame,
		CanQuery = false,
	})

	-- Ore feed running in over the roof, from the side the collector would be.
	pipeBetween(
		model,
		"Feed",
		Vector3.new(-spanX * 0.46, base + body * 0.95, -spanZ * 0.2),
		Vector3.new(-spanX * 0.1, base + body + 0.6, -spanZ * 0.2),
		0.5,
		P.Copper
	)

	local stack = height - base - body
	upright(
		model,
		"Chimney",
		spanX * 0.24,
		stack,
		CFrame.new(spanX * 0.2, base + body + stack / 2, -spanZ * 0.2),
		{ Color = P.HullShade }
	)
	for _, fraction in { 0.35, 0.7 } do
		upright(
			model,
			"ChimneyBand",
			spanX * 0.27,
			0.3,
			CFrame.new(spanX * 0.2, base + body + stack * fraction, -spanZ * 0.2),
			{ Color = P.HullDark }
		)
	end
	upright(
		model,
		"ChimneyCap",
		spanX * 0.32,
		0.5,
		CFrame.new(spanX * 0.2, height - 0.25, -spanZ * 0.2),
		{
			Color = P.Frame,
		}
	)
	-- A flared collar around the stack mouth. Chimneys widen at the top, and
	-- the flare is what keeps this from being the third plain cylinder stacked
	-- on the previous two.
	dome(
		model,
		"ChimneyFlare",
		spanX * 0.4,
		spanX * 0.1,
		CFrame.new(spanX * 0.2, height - 0.5, -spanZ * 0.2),
		{ Color = P.Frame }
	)
	glow(
		model,
		"Exhaust",
		Vector3.new(spanX * 0.18, 0.3, spanX * 0.18),
		CFrame.new(spanX * 0.2, height - 0.55, -spanZ * 0.2),
		P.Heat
	)

	ladder(model, CFrame.new(-spanX * 0.3, base, spanZ * 0.41), body * 0.9)
	railing(
		model,
		Vector3.new(-spanX * 0.4, base + body, spanZ * 0.36),
		Vector3.new(spanX * 0.4, base + body, spanZ * 0.36),
		1,
		4
	)
	statusRow(model, CFrame.new(spanX * 0.28, base + body * 0.55, spanZ * 0.41), 3, P.Heat)
end

-- The fabricator: the enclosed one. A glass bay showing a lit core says
-- "something precise happens in here" without any animation.
BUILDERS.Fabricator = function(model, spanX, spanZ, height)
	local base = plinth(model, spanX, spanZ)
	local body = height - base - 0.8

	rounded(
		model,
		"Shell",
		Vector3.new(spanX * 0.82, body, spanZ * 0.82),
		CFrame.new(0, base + body / 2, 0),
		{ Color = P.HullShade }
	)
	faceSeams(model, CFrame.new(0, base + body * 0.28, spanZ * 0.41), spanX * 0.74, body * 0.4, 4)

	piece(model, "Bay", {
		Size = Vector3.new(spanX * 0.54, body * 0.4, spanZ * 0.87),
		CFrame = CFrame.new(0, base + body * 0.6, 0),
		Color = P.Solar,
		Material = Enum.Material.Glass,
		Transparency = 0.45,
		Reflectance = 0.2,
	})
	-- Mullions across the glass. Uninterrupted glass reads as a hole.
	for index = -1, 1 do
		piece(model, "Mullion", {
			Size = Vector3.new(0.22, body * 0.44, spanZ * 0.88),
			CFrame = CFrame.new(index * spanX * 0.18, base + body * 0.6, 0),
			Color = P.Frame,
			CanQuery = false,
		})
	end

	glow(
		model,
		"Assembly",
		Vector3.new(spanX * 0.26, body * 0.18, spanZ * 0.26),
		CFrame.new(0, base + body * 0.6, 0)
	)

	-- Two gantries over the bay, plus the rail they would run on.
	for _, sx in { -1, 1 } do
		rounded(
			model,
			"Gantry",
			Vector3.new(1, body * 0.95, spanZ * 0.88),
			CFrame.new(sx * spanX * 0.31, base + body * 0.5, 0),
			{ Color = P.Frame }
		)
		pipeBetween(
			model,
			"Cable",
			Vector3.new(sx * spanX * 0.28, base + body * 0.94, -spanZ * 0.4),
			Vector3.new(sx * spanX * 0.28, base + body * 0.94, spanZ * 0.4),
			0.18,
			P.Copper
		)
	end

	rounded(
		model,
		"Roof",
		Vector3.new(spanX * 0.86, 0.7, spanZ * 0.86),
		CFrame.new(0, height - 0.45, 0),
		{ Color = P.Hull }
	)

	-- Roof plant, offset. The one thing that stops this reading as a symmetric
	-- box with a lid.
	rounded(
		model,
		"Cooler",
		Vector3.new(spanX * 0.3, 0.9, spanZ * 0.24),
		CFrame.new(-spanX * 0.22, height + 0.35, spanZ * 0.18),
		{ Color = P.HullDark }
	)
	upright(model, "Duct", 0.7, 1.2, CFrame.new(spanX * 0.24, height + 0.5, -spanZ * 0.2), {
		Color = P.HullShade,
	})

	corners(model, spanX * 0.86, spanZ * 0.86, height - 0.1, 0.7)
	statusRow(model, CFrame.new(spanX * 0.3, base + body * 0.25, spanZ * 0.42), 4, P.Status)
end

-- Commerce ------------------------------------------------------------

-- The cargo bay: the module that turns everything into credits. Hazard stripes,
-- crates and a railed apron, so it reads as a loading dock rather than as one
-- more machine.
BUILDERS.CargoBay = function(model, spanX, spanZ, height)
	local base = plinth(model, spanX, spanZ)
	local body = height - base

	rounded(
		model,
		"Hangar",
		Vector3.new(spanX * 0.86, body, spanZ * 0.58),
		CFrame.new(0, base + body / 2, -spanZ * 0.18),
		{ Color = P.Hull }
	)
	-- An arched roof over the bay. A hangar is the one building on the station
	-- with a real-world shape everybody already knows, and the arch is that
	-- shape -- it does more for "this is where the ships dock" than any amount
	-- of hazard paint on the apron.
	barrel(
		model,
		"Vault",
		spanX * 0.86,
		spanZ * 0.58,
		CFrame.new(0, base + body, -spanZ * 0.18),
		{ Color = P.HullShade }
	)
	-- Ribs across the arch, in the same spirit as the seams on a flat hull: an
	-- unbroken curve reads as plastic.
	for index = -1, 1 do
		barrel(
			model,
			"VaultRib",
			0.4,
			spanZ * 0.61,
			CFrame.new(index * spanX * 0.26, base + body, -spanZ * 0.18),
			{ Color = P.Frame, CanQuery = false }
		)
	end
	faceSeams(
		model,
		CFrame.new(0, base + body * 0.5, -spanZ * 0.47) * CFrame.Angles(0, math.rad(180), 0),
		spanX * 0.78,
		body * 0.7,
		4
	)

	piece(model, "Door", {
		Size = Vector3.new(spanX * 0.52, body * 0.74, 0.5),
		CFrame = CFrame.new(0, base + body * 0.37, spanZ * 0.11),
		Color = P.Seam,
		Material = Enum.Material.DiamondPlate,
	})
	-- Shutter slats, which is what a cargo door actually is.
	for index = 1, 4 do
		piece(model, "Slat", {
			Size = Vector3.new(spanX * 0.53, 0.16, 0.6),
			CFrame = CFrame.new(0, base + body * (0.1 + index * 0.15), spanZ * 0.11),
			Color = P.HullDark,
			CanQuery = false,
		})
	end

	glow(
		model,
		"DoorLight",
		Vector3.new(spanX * 0.52, 0.2, 0.34),
		CFrame.new(0, base + body * 0.76, spanZ * 0.11)
	)
	rounded(
		model,
		"Lintel",
		Vector3.new(spanX * 0.62, 0.6, 1),
		CFrame.new(0, base + body * 0.83, spanZ * 0.11),
		{ Color = P.Frame }
	)

	-- Hazard strip on the apron, where a crate would be set down.
	for index = 0, 4 do
		piece(model, "Hazard", {
			Size = Vector3.new(spanX * 0.12, 0.14, spanZ * 0.22),
			CFrame = CFrame.new((index - 2) * spanX * 0.16, base + 0.07, spanZ * 0.34),
			Color = if index % 2 == 0 then P.Hazard else P.Seam,
			Material = Enum.Material.SmoothPlastic,
			CanQuery = false,
		})
	end

	railing(
		model,
		Vector3.new(-spanX * 0.44, base, spanZ * 0.44),
		Vector3.new(-spanX * 0.44, base, -spanZ * 0.2),
		1.1,
		4
	)

	-- Crates: stacked, rotated differently, one on the deck. A neat stack looks
	-- placed; an untidy one looks used.
	local crates = {
		{ x = 0.3, y = 0, z = 0.3, turn = 8 },
		{ x = 0.3, y = 1, z = 0.28, turn = -14 },
		{ x = 0.18, y = 0, z = 0.36, turn = 26 },
	}
	for index, crate in crates do
		chamfered(
			model,
			"Crate",
			Vector3.new(2.1, 2, 2.1),
			CFrame.new(spanX * crate.x, base + 1 + crate.y * 2, spanZ * crate.z)
				* CFrame.Angles(0, math.rad(crate.turn), 0),
			{
				Color = if index % 2 == 0 then P.Hazard else P.Frame,
				Material = Enum.Material.Metal,
			}
		)
	end

	statusRow(model, CFrame.new(-spanX * 0.3, base + body * 0.55, spanZ * 0.12), 4, P.Status)
end

----------------------------------------------------------------------
-- Levels
--
-- A module's level is visible on the module, not just on its label. The
-- alternative -- a number floating above an unchanged box -- makes an upgrade
-- feel like a receipt rather than like a build.
--
-- A level is readable three ways, and each one works at a distance the others
-- do not:
--
--   SKIN   The palette the whole machine is painted in. This is the only one
--          that reads from across the plot, where no amount of bolted-on
--          hardware is more than a few pixels.
--   SHAPE  Hardware added per tier. Reads at walking distance, and it is what
--          makes an upgrade feel BUILT rather than repainted.
--   COUNT  One lit pip per level on the front skirt. Exact, up close, and the
--          only one of the three that answers "which level exactly".
--
-- Skin and shape together, rather than either alone: a repaint at fifty studs
-- and no new geometry at five reads as a recolour, and new geometry with no
-- repaint is invisible from anywhere a player usually stands.
--
-- The tiers are ADDITIVE and shared by all ten builders, rather than ten
-- separate models per level. Fifty hand-built variants would drift apart within
-- a week; one kit bolted onto every module keeps the progression legible and
-- identical everywhere, which is what lets a player read someone else's station
-- at a glance.
--
-- Nothing here is named in SOLID_PARTS: a tier is decoration, and a pylon a
-- player catches on at the corner of every upgraded module would be a tax on
-- the upgrade.

-- Shared with the client's upgrade burst through Balance, so the aura and the
-- spark that announces it are the same green.
local MAX_AURA_COLOUR = Color3.fromRGB(
	Balance.Vfx.Upgrade.AuraColor.R,
	Balance.Vfx.Upgrade.AuraColor.G,
	Balance.Vfx.Upgrade.AuraColor.B
)

-- The skins, as a REMAP of the palette the builders already painted with.
--
-- That indirection is what keeps ten builders times five levels from being
-- fifty pieces of code: a builder says "this face is Hull", and the level
-- decides what colour Hull is this time. Adding a sixth level is one row here,
-- not ten edits spread across the builders.
--
-- The progression is a material story rather than a rainbow -- raw plate, then
-- clean plate, then copper-braced, then dark alloy with amber furniture, then
-- pale ceramic with gold. Hue alone (blue, green, red...) would collide with
-- the readings already on these machines, where orange means heat and cyan
-- means trim. Value and finish do not collide with anything.
--
-- `polish` is Reflectance, and only ever lands on Metal: raising it on the
-- glass of a solar cell or the neon of a vent washes both out.
type Skin = {
	hull: Color3,
	shade: Color3,
	frame: Color3,
	trim: Color3,
	polish: number,
}

-- Level 1 is deliberately absent: it is the palette as built, and an identity
-- remap that walks every part to change nothing is work for no pixels.
local LEVEL_SKIN: { [number]: Skin } = {
	[2] = {
		hull = Color3.fromRGB(196, 204, 218),
		shade = Color3.fromRGB(150, 159, 180),
		frame = Color3.fromRGB(78, 86, 116),
		trim = Color3.fromRGB(72, 214, 255),
		polish = 0.04,
	},
	[3] = {
		hull = Color3.fromRGB(150, 158, 176),
		shade = Color3.fromRGB(110, 118, 140),
		frame = Color3.fromRGB(156, 102, 62),
		trim = Color3.fromRGB(120, 226, 255),
		polish = 0.09,
	},
	[4] = {
		hull = Color3.fromRGB(104, 112, 132),
		shade = Color3.fromRGB(74, 80, 98),
		frame = Color3.fromRGB(206, 150, 60),
		-- The amber of the upgrade spark. By level 4 the machine is lit in the
		-- colour of the burst that got it there.
		trim = Color3.fromRGB(255, 196, 74),
		polish = 0.17,
	},
	[5] = {
		hull = Color3.fromRGB(226, 231, 240),
		shade = Color3.fromRGB(176, 184, 200),
		frame = Color3.fromRGB(222, 176, 84),
		-- Topped out, so the trim joins the aura rather than arguing with it.
		trim = MAX_AURA_COLOUR,
		polish = 0.24,
	},
}

local TOP_SKIN = 5

-- Applied LAST, over the tier hardware as well as the hull. The order is the
-- point: reskinning first and then bolting on pylons painted from the base
-- palette gives a level-4 machine level-1 furniture.
--
-- The aura is unaffected because its green is in no swap -- it is not a
-- palette role, and that is precisely why it was given a colour the palette
-- does not otherwise use.
local function reskin(model: Model, level: number)
	local skin = LEVEL_SKIN[math.min(level, TOP_SKIN)]
	if not skin then
		return
	end

	-- Colour equality on Color3 is by value, so a part painted P.Hull matches
	-- whatever builder painted it, in any module, without anything having to
	-- be tagged.
	local swaps = {
		{ from = P.Hull, to = skin.hull, metal = true },
		{ from = P.HullShade, to = skin.shade, metal = true },
		{ from = P.Frame, to = skin.frame, metal = false },
		{ from = P.Trim, to = skin.trim, metal = false },
	}

	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			for _, swap in swaps do
				if descendant.Color == swap.from then
					descendant.Color = swap.to
					if swap.metal and descendant.Material == Enum.Material.Metal then
						descendant.Reflectance = skin.polish
					end
					break
				end
			end
		end
	end
end

-- Centred on the module's own axis, so the row needs the depth to sit on the
-- front face but never the width.
local function levelPips(model: Model, spanZ: number, level: number)
	-- One lit pip per level along the front skirt. Countable at a glance, which
	-- a colour ramp is not.
	local pitch = 1.1
	for index = 0, level - 1 do
		local x = (index - (level - 1) / 2) * pitch
		piece(model, "LevelPip", {
			Size = Vector3.new(0.55, 0.22, 0.28),
			CFrame = CFrame.new(x, 0.3, spanZ / 2 + 0.02),
			Color = P.Trim,
			Material = Enum.Material.Neon,
			CanQuery = false,
		})
	end
end

-- Every tier is built from the same round vocabulary as the modules it bolts
-- onto. Square furniture on a filleted hull reads as scaffolding somebody
-- forgot to take down.
local function tierHardware(
	model: Model,
	spanX: number,
	spanZ: number,
	height: number,
	level: number
)
	if level >= 2 then
		-- Corner posts: the first upgrade has to be visible from across the
		-- plot, or the player wonders whether it took. Capsules -- a cylinder
		-- under a hemisphere -- rather than the boxes this tier used to be.
		for _, sx in { -1, 1 } do
			for _, sz in { -1, 1 } do
				local x, z = sx * (spanX / 2 - 0.7), sz * (spanZ / 2 - 0.7)
				upright(model, "TierPost", 0.52, 1.4, CFrame.new(x, 0.75 + 0.7, z), {
					Color = P.Frame,
					CanQuery = false,
				})
				dome(model, "TierPostCrown", 0.52, 0.26, CFrame.new(x, 0.75 + 1.4, z), {
					Color = P.Trim,
					Material = Enum.Material.Neon,
					CanQuery = false,
				})
			end
		end
	end

	if level >= 3 then
		-- A collar lifting off the plinth, in two steps rather than one slab.
		-- Two diameters read as a turned fitting; one reads as a coaster.
		upright(
			model,
			"TierCollar",
			math.min(spanX, spanZ) * 0.94,
			0.26,
			CFrame.new(0, 1.03, 0),
			{ Color = P.HullDark, CanQuery = false }
		)
		upright(
			model,
			"TierCollarStep",
			math.min(spanX, spanZ) * 0.82,
			0.24,
			CFrame.new(0, 1.26, 0),
			{ Color = P.Frame, CanQuery = false }
		)
	end

	if level >= 4 then
		-- Vanes on the diagonal, canted outward: the silhouette changes, not
		-- just the surface. Filleted and domed at the tip, so they read as
		-- cast fins instead of as planks leaning on the machine.
		for index = 0, 1 do
			local angle = math.rad(45 + index * 180)
			local at = CFrame.new(
				math.cos(angle) * spanX * 0.42,
				height * 0.34,
				math.sin(angle) * spanZ * 0.42
			) * CFrame.Angles(0, -angle, math.rad(14))

			rounded(model, "TierVane", Vector3.new(0.34, height * 0.34, 1.6), at, {
				Color = P.HullShade,
				CanQuery = false,
			})
			dome(model, "TierVaneTip", 1.2, 0.6, at * CFrame.new(0, height * 0.17, 0), {
				Color = P.HullShade,
				CanQuery = false,
			})
			glow(
				model,
				"TierVaneEdge",
				Vector3.new(0.14, height * 0.3, 0.2),
				CFrame.new(
					math.cos(angle) * spanX * 0.44,
					height * 0.34,
					math.sin(angle) * spanZ * 0.44
				) * CFrame.Angles(0, -angle, math.rad(14))
			)
		end
	end
end

-- The aura, in two strengths.
--
-- It starts one level BEFORE the top, faintly: a module that is nearly there
-- should look nearly there, and it gives the last upgrade something visible to
-- complete rather than something to switch on from nothing.
--
-- HOW MUCH IS TOO MUCH. Two rules, both learned by overshooting:
--
--   Nothing tall. The first version put four neon spires half the module's
--   height up its corners. On one module it looked like a monument; on a plot
--   with six topped-out modules it was a fence of green bars standing between
--   the player and their own station. Everything the aura is made of now sits
--   either at ankle height or above the roofline -- the band at eye level,
--   which is the band a player actually needs to see through, is left empty.
--
--   Nothing enclosing. The version before that wrapped the machine in a
--   translucent green shell. Even at 0.88 transparency it tinted the whole
--   hull: it read as a module someone had PAINTED green, not one that was
--   glowing, and it hid the very geometry the upgrade had just added.
--
-- So the aura is light NEXT TO the machine, never around it or over it. The
-- ground ring stays inside the footprint on purpose as well: a ring wider than
-- the module spills onto the neighbouring plot's deck, and two adjacent
-- topped-out modules then share one green puddle.
local function aura(model: Model, spanX: number, spanZ: number, height: number, full: boolean)
	-- Green because nothing else on the station is: cyan is trim, orange is
	-- heat, yellow is money. A colour the palette does not otherwise use cannot
	-- be mistaken for a reading.
	local ring =
		upright(model, "AuraRing", math.max(spanX, spanZ) * 1.02, 0.16, CFrame.new(0, 0.12, 0), {
			Color = MAX_AURA_COLOUR,
			Material = Enum.Material.Neon,
			Transparency = if full then 0.15 else 0.5,
			CanQuery = false,
		})

	-- Short range and low brightness. A PointLight big enough to "look
	-- powerful" tints every neighbouring hull green, and the module then reads
	-- as the thing making everything else look wrong.
	local light = Instance.new("PointLight")
	light.Color = MAX_AURA_COLOUR
	light.Range = if full then 13 else 9
	light.Brightness = if full then 0.8 else 0.35
	light.Parent = ring

	if not full then
		return
	end

	-- Above the roofline, so it is in the sky rather than in the way.
	upright(
		model,
		"AuraHalo",
		math.max(spanX, spanZ) * 0.62,
		0.16,
		CFrame.new(0, height + 0.55, 0),
		{
			Color = MAX_AURA_COLOUR,
			Material = Enum.Material.Neon,
			Transparency = 0.3,
			CanQuery = false,
		}
	)

	-- Ankle-height corner marks. They pick the footprint out of the deck from
	-- directly above, which is the one angle the ring alone reads weakly from.
	--
	-- Seated so the sphere's underside lands exactly on y = 0. `dome` centres a
	-- full sphere on its anchor and expects the lower half to be buried in
	-- whatever it caps -- here there is nothing under it but the module's own
	-- base plane, and half a bead hanging through it would break the "base at
	-- y = 0" contract the scene builder pivots against.
	local markRadius = 0.3
	for index = 0, 3 do
		local angle = math.rad(45 + index * 90)
		dome(
			model,
			"AuraMark",
			markRadius * 2,
			markRadius,
			CFrame.new(math.cos(angle) * spanX * 0.44, markRadius, math.sin(angle) * spanZ * 0.44),
			{ Color = MAX_AURA_COLOUR, Material = Enum.Material.Neon, CanQuery = false }
		)
	end
end

local function applyLevel(
	model: Model,
	spanX: number,
	spanZ: number,
	height: number,
	level: number,
	maxLevel: number
)
	if level <= 1 then
		return
	end
	levelPips(model, spanZ, level)
	tierHardware(model, spanX, spanZ, height, level)
	-- `maxLevel` is math.huge when the caller does not know it, and both
	-- comparisons are then false -- an unknown ceiling shows no aura rather
	-- than showing the top-level one on every module.
	--
	-- The switch is a balance value rather than a deleted call: the aura is a
	-- taste decision, and taste decisions get turned back on.
	if Balance.Vfx.Upgrade.MaxAura and level >= maxLevel - 1 then
		aura(model, spanX, spanZ, height, level >= maxLevel)
	end
	reskin(model, level)
end

----------------------------------------------------------------------

-- Collision is applied here, once, instead of inside each builder. Note this is
-- NOT the blanket `CanCollide = true` StationSceneBuilder applies to an authored
-- template: that made every greeble solid, which a hand-made model gets away
-- with only because it has no greebles.
local function applyCollision(model: Model)
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			-- Neon is light, never mass -- and the strips are exactly the thin
			-- shapes a character catches on.
			descendant.CanCollide = descendant.Material ~= Enum.Material.Neon
				and (
					SOLID_PARTS[descendant.Name]
					or SOLID_PARTS[solidBase(descendant.Name)] == true
				)
		end
	end
end

function ModuleGeometry.has(id: string): boolean
	return BUILDERS[id] ~= nil
end

-- Returns a model built at the origin with its base at y = 0, ready for the
-- caller to pivot into place. `cellSize` is the only thing that turns a
-- catalogue size into studs, which is why it is a parameter rather than a
-- constant in here.
function ModuleGeometry.build(
	definition: any,
	cellSize: number,
	level: number?,
	maxLevel: number?
): Model?
	local builder = BUILDERS[definition.id]
	if not builder then
		return nil
	end

	local model = Instance.new("Model")
	model.Name = definition.id

	local spanX = definition.size.w * cellSize - SEAM_GAP
	local spanZ = definition.size.h * cellSize - SEAM_GAP
	local height = VISUAL_HEIGHT[definition.id] or definition.height
	builder(model, spanX, spanZ, height)
	applyLevel(model, spanX, spanZ, height, level or 1, maxLevel or math.huge)

	applyCollision(model)

	-- A fresh Model puts its pivot at the centre of its bounding box, which
	-- would offset every module by half its height the moment it is placed.
	-- Setting it explicitly is what makes the "base at y = 0" contract true.
	model.WorldPivot = CFrame.new()
	model.PrimaryPart = nil

	return model
end

-- Rebuilds an already-placed model's geometry at a new level, IN PLACE.
--
-- The instance is kept rather than replaced, and that is the whole point: the
-- client has a label parented to this model and an attribute-changed connection
-- watching it. Destroying and re-adding the model would silently drop both, and
-- the upgrade would land with the label gone and no spark.
--
-- Only the parts this module built are cleared. Anything else a client parented
-- onto the model is left where it is.
function ModuleGeometry.restyle(
	model: Model,
	definition: any,
	cellSize: number,
	level: number,
	maxLevel: number?
): boolean
	local builder = BUILDERS[definition.id]
	if not builder then
		return false
	end

	local pivot = model:GetPivot()

	for _, child in model:GetChildren() do
		if child:IsA("BasePart") then
			child:Destroy()
		end
	end

	local spanX = definition.size.w * cellSize - SEAM_GAP
	local spanZ = definition.size.h * cellSize - SEAM_GAP
	local height = VISUAL_HEIGHT[definition.id] or definition.height
	builder(model, spanX, spanZ, height)
	applyLevel(model, spanX, spanZ, height, level, maxLevel or math.huge)
	applyCollision(model)

	-- The parts were just built around the origin, so the pivot has to be
	-- returned to the origin before the model is put back where it stood.
	model.WorldPivot = CFrame.new()
	model.PrimaryPart = nil
	model:PivotTo(pivot)

	return true
end

return ModuleGeometry
