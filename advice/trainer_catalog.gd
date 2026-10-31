extends RefCounted
## Data only: trainer id, display name, and rule definitions consumed by rule_factory.gd.
## Adding a trainer = adding one entry here (plus a trainers/<id>.gd only if it needs
## custom evaluate() logic, referenced via the "script" key in a rule definition).

# Items stay empty: basic_bait changed in-game and is no longer reminder worthy.
const DEFAULT_SHOP_MONSTERS := ["monster.name.lamplet", "monster.name.swoonet"]
const DEFAULT_SHOP_ITEMS := []
const DEFAULT_SHOP_SEVERITY := "NOTICE"
const DEFAULT_SHOP_MESSAGE := "Shop targets: %s | Level-up/trinket opportunities"

const TRAINER_DEFINITIONS := [
	{
		"id": "scavenger",
		"display_name": "Scavenger",
		"rules": [
			{
				"type": "shop_targets",
				"rule_id": "scavenger_targets",
				"monsters": DEFAULT_SHOP_MONSTERS,
				"items": DEFAULT_SHOP_ITEMS,
				"severity": DEFAULT_SHOP_SEVERITY,
				"message_template": DEFAULT_SHOP_MESSAGE
			}
		]
	},
	{
		"id": "treasure_hunter",
		"display_name": "Treasure Hunter",
		"rules": [
			{
				"type": "shop_targets",
				"rule_id": "treasure_hunter_targets",
				"monsters": DEFAULT_SHOP_MONSTERS,
				"items": DEFAULT_SHOP_ITEMS,
				"severity": DEFAULT_SHOP_SEVERITY,
				"message_template": DEFAULT_SHOP_MESSAGE
			}
		]
	},
	{
		"id": "burglar",
		"display_name": "Burglar",
		"rules": [
			{
				"type": "shop_targets",
				"rule_id": "burglar_targets",
				"monsters": DEFAULT_SHOP_MONSTERS,
				"items": DEFAULT_SHOP_ITEMS,
				"severity": DEFAULT_SHOP_SEVERITY,
				"message_template": DEFAULT_SHOP_MESSAGE
			}
		]
	},
	{
		"id": "black_belt",
		"display_name": "Black Belt",
		"rules": [
			{
				"type": "shop_targets",
				"rule_id": "blackbelt_beetbud",
				"monsters": ["monster.name.beetbud"],
				"items": [],
				"severity": "NOTICE",
				"message_template": "Beetbud available: shop %s"
			},
			{
				"type": "shop_targets",
				"rule_id": "blackbelt_fighting",
				"target_types": ["fighting"],
				"monsters": [],
				"items": [],
				"severity": "NOTICE",
				"message_template": "Fighter available: shop %s"
			},
			{
				"type": "team_composition",
				"rule_id": "beetdown_company",
				"monster_key": "monster.name.beetdown",
				"min_level": 3,
				"required_type": "fighting",
				"severity": "WARNING",
				"message": "Beetdown needs to be your only fighter. Other fighters: %s",
				"reminder": "Black Belt: 2+ Fighters active!"
			}
		]
	},
	{
		"id": "mad_scientist",
		"display_name": "Mad Scientist",
		"rules": [
			{
				"type": "day_reminder",
				"rule_id": "mad_scientist_day6",
				"day": 6,
				"severity": "WARNING",
				"message": "MAD SCIENTIST: Your active team transforms into random Legendaries on Day 7!",
				"reminder": "Tomorrow: Legendary transformation!"
			}
		]
	},
	{
		"id": "gamer",
		"display_name": "Gamer",
		"rules": [
			{
				"type": "day_reminder",
				"rule_id": "gamer_day8",
				"day": 8,
				"severity": "NOTICE",
				"message": "GAMER: A Mythical monster arrives on Day 9!",
				"reminder": "Tomorrow: Mythical monster!"
			}
		]
	},
	{
		"id": "gentleman",
		"display_name": "Gentleman",
		"rules": [
			{
				"type": "day_reminder",
				"rule_id": "gentleman_day3",
				"day": 3,
				"severity": "NOTICE",
				"message": "GENTLEMAN: Common and Uncommon monsters stop appearing in shops starting Day 4!",
				"reminder": "Tomorrow: No Common/Uncommon shops!"
			}
		]
	},
	{
		"id": "musician",
		"display_name": "Musician",
		"rules": [
			{
				"type": "shop_targets",
				"rule_id": "musician_electric_shop",
				"target_types": ["electric"],
				"monsters": [],
				"items": [],
				"severity": "NOTICE",
				"message_template": "Electric available: shop %s"
			},
			{
				"type": "team_composition",
				"rule_id": "musician_electric_limit",
				"required_type": "electric",
				"severity": "WARNING",
				"message": "Musician: %s Electric monsters active (only 1 allowed)",
				"reminder": "Musician: 2+ Electric monsters!"
			}
		]
	},
	{
		"id": "bug_catcher",
		"display_name": "Bug Catcher",
		"rules": [
			{
				"type": "shop_targets",
				"rule_id": "bug_catcher_bug",
				"target_types": ["bug"],
				"monsters": [],
				"items": [],
				"severity": "NOTICE",
				"message_template": "Bug available: shop %s"
			}
		]
	},
	{
		"id": "chemist",
		"display_name": "Chemist",
		"rules": [
			{
				"type": "shop_targets",
				"rule_id": "chemist_toxic",
				"target_types": ["toxic"],
				"monsters": [],
				"items": [],
				"severity": "NOTICE",
				"message_template": "Toxic available: shop %s"
			}
		]
	},
	{
		"id": "redhead",
		"display_name": "Redhead",
		"rules": [
			{
				"type": "shop_targets",
				"rule_id": "redhead_fire",
				"target_types": ["fire"],
				"monsters": [],
				"items": [],
				"severity": "NOTICE",
				"message_template": "Fire available: shop %s"
			}
		]
	}
]