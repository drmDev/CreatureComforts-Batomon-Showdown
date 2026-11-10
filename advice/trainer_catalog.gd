extends RefCounted
## Data only: trainer id, display name, and rule definitions consumed by rule_factory.gd.
## Adding a trainer = adding one entry here (plus a trainers/<id>.gd only if it needs
## custom evaluate() logic, referenced via the "script" key in a rule definition).

const TRAINER_DEFINITIONS := [
	{
		"id": "black_belt",
		"display_name": "Black Belt",
		"rules": [
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
				"rule_id": "gamer_day7",
				"day": 7,
				"severity": "NOTICE",
				"message": "GAMER: A Mythical monster arrives on Day 8!",
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
				"type": "team_composition",
				"rule_id": "musician_electric_limit",
				"required_type": "electric",
				"severity": "WARNING",
				"message": "Musician: %s Electric monsters active (only 1 allowed)",
				"reminder": "Musician: 2+ Electric monsters!"
			}
		]
	}
]

# Trainer-independent day reminders. Built with an empty trainer id, so they
# apply to every trainer (see BaseRule._matches_trainer). Each fires once on
# its trigger day, the day before the event.
const GLOBAL_RULES := [
	{
		"type": "day_reminder",
		"rule_id": "global_day3_event",
		"day": 2,
		"severity": "NOTICE",
		"message": "GLOBAL: Day 3 event tomorrow!",
		"reminder": "Tomorrow: Day 3 event!"
	},
	{
		"type": "day_reminder",
		"rule_id": "global_day6_event",
		"day": 5,
		"severity": "NOTICE",
		"message": "GLOBAL: Day 6 event tomorrow!",
		"reminder": "Tomorrow: Day 6 event!"
	},
	{
		"type": "day_reminder",
		"rule_id": "global_day9_event",
		"day": 8,
		"severity": "NOTICE",
		"message": "GLOBAL: Day 9 event tomorrow!",
		"reminder": "Tomorrow: Day 9 event!"
	}
]