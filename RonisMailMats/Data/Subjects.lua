-- Mail subjects, one picked at random per draft. Keyed by what the mail
-- holds: a profession or skill, "Upgrades", "class" (spell reagents; {class}
-- is the class name) and "default" (custom groups and mixed mails; {what} is
-- what is sent). Keep them short: the subject box holds 64 characters.
local _, ns = ...
ns.SUBJECTS = {
    Tailoring = {
        "Cloth for the loom", "Fresh off the bolt", "Stitch this", "Thread and fabric",
        "For your sewing basket", "A bundle of cloth", "Needle work ahead", "Bolts incoming",
        "Spin me something nice", "Tailor's delivery", "Cloth, as promised", "Fabric run",
    },
    Leatherworking = {
        "Hides for the tannery", "Leather delivery", "Skins and scraps", "Fresh from the skinning knife",
        "Tan these", "A stack of hides", "For your leather kit", "Supple goods",
        "Scales and skins", "Straight off the beast", "Leatherworker's crate", "Hide run",
    },
    Blacksmithing = {
        "Metal for the anvil", "Bars for the forge", "Hammer time", "Smith's delivery",
        "Stoke the forge", "Heavy mail, literally", "Ingots incoming", "For your anvil",
        "Strike while it is hot", "Ore and bars", "Forge fuel", "Steel yourself",
    },
    Engineering = {
        "Parts for the workshop", "Bolts and bits", "Do not shake this box", "Gizmo supplies",
        "For your next invention", "Spare parts", "Handle with goggles", "Tinker's crate",
        "Some assembly required", "Boom supplies", "Gears and gadgets", "Workshop delivery",
    },
    Alchemy = {
        "Herbs for the cauldron", "Fresh herbs", "Brew something good", "Alchemist's delivery",
        "Petals and roots", "For your vials", "Potion fodder", "Garden run",
        "Mix these", "Herbal care package", "Flask fuel", "Pick of the crop",
    },
    Enchanting = {
        "Dust and shards", "Disenchant fodder", "Sparkly stuff", "For your rod",
        "Magic in a box", "Enchanter's delivery", "Greens to dust", "Arcane supplies",
        "Shiny things to break", "Glowing goods", "Essence run", "Make it glow",
    },
    Mining = {
        "Ore for the smelter", "Rocks, the good kind", "Smelt these", "Miner's delivery",
        "Fresh from the vein", "Stone and ore", "Heavy rocks inside", "Pickaxe proceeds",
        "Straight from the mine", "Ore run", "For your furnace", "Dig this",
    },
    Cooking = {
        "Ingredients for the pot", "Something to cook", "Kitchen delivery", "Dinner supplies",
        "Fresh meat and spices", "Chef's crate", "For your cookbook", "Fire up the grill",
        "Feed the raid", "Pantry run", "Grub supplies", "Taste test inside",
    },
    ["First Aid"] = {
        "Cloth for bandages", "Patch them up", "Medic's delivery", "Bandage supplies",
        "For your first aid kit", "Wrap these wounds", "Field medicine", "Keep them alive",
        "Healer's crate", "Linen for the injured", "Triage supplies", "Doctor's orders",
    },
    Poisons = {
        "Vials and venom", "Handle with gloves", "Poison supplies", "For your blades",
        "Do not drink this", "Toxic delivery", "Rogue's crate", "Coat your daggers",
        "Mind the fumes", "Venom run", "Something nasty", "Shady supplies",
    },
    Lockpicking = {
        "Boxes to crack", "Locked and loaded", "Pick these", "Lockboxes inside",
        "Practice for your picks", "What is in the box", "Open sesame", "Rogue homework",
        "Crack me open", "Secrets inside, probably", "Locksmith's delivery", "Treasure, maybe",
    },
    Comprehension = {
        "Scrolls to read", "Words of power", "For your reading list", "Strange scrolls",
        "Read these aloud", "Study material", "Arcane homework", "Mysterious writings",
        "Scroll delivery", "Ancient words", "Bookworm supplies", "Decipher this",
    },
    Upgrades = {
        "Gear upgrade", "Something to wear", "New gear for you", "Try this on",
        "Better than what you have", "Fashion delivery", "Stat boost inside", "Dress for success",
        "Fresh gear", "Upgrade incoming", "Swap that old piece", "Looking sharp",
    },
    class = {
        "{class} supplies", "Reagents for your spells", "Spell components", "Restock time",
        "For your spellbook", "{class} reagents", "Do not run out", "Topping you up",
        "Spell fuel", "Components inside", "Bag of reagents", "Cast away",
    },
    default = {
        "Your {what}", "Some {what} for you", "Delivery: {what}", "Package inside",
        "Supplies for you", "From your favorite alt", "A little something", "Care package",
        "Special delivery", "Mail call", "Stuff for you", "Open me",
    },
}
