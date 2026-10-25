extends RefCounted
## TrinketDescriptions - Catalog of trinket summaries for display
## Maps trinket IDs to compact effect descriptions

# Trinket ID → compact summary mapping
# IDs are snake_case runtime identifiers (e.g., "fire_bell", "gold_trophy")
# Summaries preserve exact targets, amounts, triggers, durations, and exclusions
const DESCRIPTIONS := {
	"alpha_crown": "Battle start: all your monsters match the top-middle monster's damage for that battle.",
	"ancient_plume": "Battle start, with exactly one monster: permanently grant it 1 multicast; consume this trinket.",
	"arcade_coins": "Grants 10 free shop rerolls.",
	"barbell": "Increases HP by 5,000.",
	"bargain_bin": "Each day, your first Common monster purchase costs nothing.",
	"blitz_bell": "Shop monsters receive 25% additional cooldown speed.",
	"blue_incense": "Restricts the next five shops to Rare monsters.",
	"boxing_glove": "Victory: permanently add 5 damage to your team.",
	"bug_net": "Reduces shop prices for Bug monsters by 3 gold.",
	"candy_jar": "Battle start: permanently raise your Common and Uncommon monsters to level 3.",
	"dryad_charm": "Increases HP by 30%.",
	"earth_crest": "Battle start: permanently increase rightmost-column monsters' shield by 10%.",
	"echo_bell": "Buying a zero-cost item activates it one extra time.",
	"echo_charm": "Your monsters' On Bought abilities activate one extra time.",
	"excalibur": "Adds 350 damage to your monsters.",
	"fake_diamond": "Your next battle defeat awards 40 gold.",
	"fancy_sword": "Your monsters receive 3% additional damage per owned trinket.",
	"fire_bell": "Shop monsters of the Fire type receive 5 additional burn.",
	"fire_orb": "Adds 3 burn to your Fire monsters.",
	"fool_gold": "Adds 15 gold to income; removes items from shop stock.",
	"giant_club": "Monsters with cooldowns of at least 5 seconds receive 70% additional stats, excluding cooldown and multicast.",
	"gold_bar": "Adds 10 gold to income.",
	"gold_bracelet": "Day begins: one randomly selected monster receives 8 additional sell value.",
	"gold_incense": "Restricts the next five shops to Legendary monsters.",
	"gold_nugget": "Adds 3 gold to income.",
	"gold_trophy": "Victory awards 8 gold.",
	"gold_o_matic": "Adds 30 gold to income.",
	"greedy_gloves": "Allows taking every option from your next trinket gift.",
	"grow_lamp": "Your Grass monsters require only two copies to level up.",
	"haste_crown": "Top-middle monster receives 20% additional cooldown speed.",
	"haste_orb": "Your monsters receive 10% additional cooldown speed.",
	"hero_sword": "Adds 12 damage to your monsters.",
	"holy_grail": "Victory awards 100 gold.",
	"junk": "Provides no effect.",
	"kaleidoscope": "Monsters sharing no type with any ally receive 25% additional cooldown speed.",
	"link_cable": "Treats every monster on your team as adjacent to every other teammate.",
	"locked_box": "Your next battle defeat grants a random non-unique trinket from the highest rarity permitted by your shop rank.",
	"market_license": "Raises shop rank by one.",
	"master_crown": "Top-middle monster receives 80% additional stats, excluding cooldown and multicast.",
	"mega_duplicator": "Your next non-unique trinket received from a gift comes with two extra copies.",
	"mega_upgrade_disc": "When a monster reaches level 3, grant another level and consume this trinket.",
	"membership_card": "Allows one extra item use per day.",
	"metal_bat": "Battle start: your highest-cooldown monster receives 50% additional damage for that battle.",
	"meteorite": "Battle start: permanently add 20 damage to your monsters that have no abilities.",
	"metronome": "Each cast adds 10 damage to the casting monster for that battle.",
	"mighty_bell": "Adds 300 damage to shop monsters.",
	"mini_duplicator": "Your next non-unique trinket received from a gift comes with one extra copy.",
	"momentum_flag": "Battle start: permanently increase leftmost-column monsters' cooldown speed by 8%.",
	"mysterious_charm": "Increases HP by 25%.",
	"mysterious_chest": "Battle defeat grants a random non-unique Legendary trinket.",
	"mysterious_gem": "Your monsters receive 20% additional damage.",
	"mysterious_mask": "Lets you select a trainer and acquire their ability.",
	"mystic_incense": "Guarantees a Mythical monster in your next shop.",
	"piggy_bank": "Day ends: receive 1 gold per 10 gold held.",
	"poison_bell": "Shop monsters of the Toxic type receive 6 additional poison.",
	"poison_orb": "Adds 3 poison to your Toxic monsters.",
	"power_band": "Your first monster purchase each day receives 20 additional damage.",
	"power_bell": "Adds 25 damage to shop monsters.",
	"power_crown": "Adds 20 damage to your top-middle monster.",
	"power_pouch": "Each item purchase adds 2 damage to your monsters.",
	"purple_incense": "Restricts the next five shops to Super Rare monsters.",
	"quick_bell": "Shop monsters receive 4% additional cooldown speed.",
	"quick_flag": "Leftmost-column monsters receive 4% additional cooldown speed.",
	"rainbow_berry": "Your monsters receive 4 additional damage per distinct type represented on your team.",
	"rainbow_pearl": "Makes every shop monster shiny.",
	"rally_flag": "Battle start: permanently add 12 damage to leftmost-column monsters.",
	"razor_beak": "Adds 1 multicast to your Flying monsters.",
	"repeater_charm": "Your monsters' On Battle Start abilities activate one extra time.",
	"research_notes": "Substantially increases the likelihood of Legendary monsters appearing in shops.",
	"rigged_dice": "Each day's first shop contains only monsters and items of the highest rarity your shop rank permits.",
	"rocket_boots": "Adds the Flying type to shop monsters.",
	"sapphire_amulet": "Increases healing you receive by 25%.",
	"sapphire_ring": "Shop monsters receive 10% additional heal.",
	"scrap_sword": "Your monsters receive 2 additional damage per owned Common trinket.",
	"sea_crest": "Battle start: permanently increase rightmost-column monsters' heal by 10%.",
	"silver_watch": "A monster leveling up through merging receives 12% additional cooldown speed.",
	"small_club": "Monsters with cooldowns of at least 5 seconds receive 20% additional damage.",
	"speed_crest": "Rightmost-column monsters receive 15% additional cooldown speed.",
	"speed_whistle": "Your next purchased monster receives 12% additional cooldown speed.",
	"tempo_charm": "Battle start: permanently grant one randomly selected monster 4% additional cooldown speed.",
	"terrarium": "Your Bug monsters receive 20% additional damage.",
	"topaz_amulet": "Increases shielding you receive by 25%.",
	"topaz_ring": "Shop monsters receive 10% additional shield.",
	"training_weights": "Increases HP by 100.",
	"treasure_map": "Raises the rarity of your next trinket gift's options by one tier.",
	"ultra_duplicator": "Each non-unique trinket received from a gift comes with one extra copy.",
	"upgrade_disc": "Level up a monster when you buy it, then consume this trinket.",
	"vip_pass": "Removes Common and Uncommon stock from your shop.",
	"warhorn": "Battle start: permanently add 10 damage to your monsters.",
	"winged_crown": "Adds 1 multicast to your top-middle monster.",
	"winged_fossil": "Your Flying monsters receive 25% additional stats, excluding cooldown and multicast.",
	"wood_sword": "Adds 5 damage to your monsters.",
	"zenith_stone": "Amplifies your monsters' stat gains by 80%, excluding multicast and percentage bonuses.",
}


func get_description(trinket_id: String) -> String:
	"""Get the compact summary for a trinket ID. Returns empty string if not found."""
	return DESCRIPTIONS.get(trinket_id, "")


func has_description(trinket_id: String) -> bool:
	"""Check if a description exists for the given trinket ID."""
	return DESCRIPTIONS.has(trinket_id)


func get_all_ids() -> Array:
	"""Get all known trinket IDs."""
	return DESCRIPTIONS.keys()


func get_count() -> int:
	"""Get the total number of cataloged trinkets."""
	return DESCRIPTIONS.size()
