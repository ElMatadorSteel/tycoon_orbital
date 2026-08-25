--!strict
-- The onboarding objective chain. Pure data, ported as-is from the legacy
-- Shared/Objectives -- text lives only here, never crosses the network as a
-- string (the server sends an index, the client looks the text up itself).
--
-- The chain is built to lead to THE rule of the game: a corridor carries
-- nothing, conduits are required. The first five objectives raise the
-- situation where that rule becomes visible; the last one enforces it.
--
-- The budget is sized to hold: starting at 800 credits, the collector costs
-- 300 and the cargo bay 400. The rewards fund what comes next, or the
-- player would be stuck in front of an objective they can't afford.

export type Objective = {
	id: string,
	title: string,
	hint: string,
	reward: number,
}

export type Completion = {
	title: string,
	subtitle: string,
	gift: string,
	reward: number,
}

local Objectives = {}

Objectives.List = {
	{
		id = "Embark",
		title = "Rejoins ta station",
		hint = "Monte sur la passerelle au centre du lobby et appuie sur E.",
		reward = 0,
	},
	{
		id = "Collector",
		title = "Pose un collecteur",
		hint = "Appuie sur B pour ouvrir le menu. Le collecteur capte le minerai des débris en orbite.",
		reward = 150,
	},
	{
		id = "Sell",
		title = "Relie une soute au collecteur",
		hint = "Sans soute, le minerai ne se vend pas. Colle-la contre le collecteur.",
		reward = 200,
	},
	{
		id = "Solar",
		title = "Pose un panneau solaire",
		hint = "Ta station consomme plus que le noyau ne produit : tout tourne au ralenti.",
		reward = 200,
	},
	{
		id = "Radiator",
		title = "Pose un radiateur",
		hint = "Laisse-lui du vide autour : un radiateur enfermé entre deux modules ne dissipe rien.",
		reward = 250,
	},
	{
		id = "Conduit",
		title = "Fais travailler un conduit",
		hint = "Prolonge ta station avec deux ou trois conduits, puis pose un collecteur au bout. Une coursive ne transporterait rien.",
		reward = 400,
	},
} :: { Objective }

Objectives.Count = #Objectives.List

-- Deliberately symbolic: it must be felt, not change the balance. 100
-- credits when the last objective already gives 400 and a cargo bay costs
-- 400 -- enough to feel like a gain, not enough to skip a step.
Objectives.Completion = {
	title = "MISSION RÉUSSIE",
	subtitle = "Ta station tourne toute seule. La suite est à toi.",
	gift = "Balise commémorative dorée",
	reward = 100,
} :: Completion

function Objectives.get(index: number): Objective?
	return Objectives.List[index]
end

return Objectives
