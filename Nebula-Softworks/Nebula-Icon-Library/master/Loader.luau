-- ── Load Starlight ────────────────────────────────────────────────────────────
local Starlight   = loadstring(game:HttpGet("https://raw.nebulasoftworks.xyz/starlight"))()
local NebulaIcons = loadstring(game:HttpGet("https://raw.nebulasoftworks.xyz/nebula-icon-library-loader"))()

-- ── Apply dropdown search patch ───────────────────────────────────────────────
loadstring(game:HttpGet("https://YOUR_RAW_URL/starlight_dropdown_search.lua"))()(Starlight)

-- ── Build a minimal window ────────────────────────────────────────────────────
local Window = Starlight:CreateWindow({
    Name     = "Search Test",
    Subtitle = "Dropdown Search Patch",
    Icon     = NebulaIcons:GetIcon("search", "Lucide"),
    LoadingSettings = { Title = "Search Test", Subtitle = "Loading..." },
    FileSettings    = { ConfigFolder = "DropdownSearchTest" },
})

Window:CreateHomeTab({
    SupportedExecutors   = { "Synapse Z", "Scriptware", "Wave" },
    UnsupportedExecutors = {},
    Changelog = {{ Title = "v1", Date = "Today", Description = "Testing dropdown search" }},
})

-- ── Tab with a few dropdowns to test ─────────────────────────────────────────
local Section = Window:CreateTabSection("Test")
local Tab     = Section:CreateTab({
    Name    = "Dropdowns",
    Icon    = NebulaIcons:GetIcon("list", "Lucide"),
    Columns = 2,
}, "TestTab")

local Box1 = Tab:CreateGroupbox({ Name = "Single Select", Column = 1 }, "Box1")
local Box2 = Tab:CreateGroupbox({ Name = "Multi Select",  Column = 2 }, "Box2")

-- ── Single-select dropdown with lots of options ───────────────────────────────
Box1:CreateLabel({ Name = "Pick a fruit" }, "lbl1"):AddDropdown({
    Options = {
        "Apple", "Apricot", "Avocado",
        "Banana", "Blueberry", "Blackberry",
        "Cherry", "Coconut", "Cranberry",
        "Date", "Dragonfruit", "Durian",
        "Elderberry", "Fig", "Grape",
        "Guava", "Jackfruit", "Kiwi",
        "Lemon", "Lime", "Lychee",
        "Mango", "Melon", "Nectarine",
        "Orange", "Papaya", "Passionfruit",
        "Peach", "Pear", "Pineapple",
        "Plum", "Pomegranate", "Raspberry",
        "Strawberry", "Watermelon",
    },
    CurrentOption = {},
    MultipleOptions = false,
    Placeholder = "Type to search...",
    Callback = function(v)
        print("[Single] Selected:", v[1])
    end,
}, "drop_single")

-- ── Multi-select dropdown with player-style names ─────────────────────────────
Box2:CreateLabel({ Name = "Pick players" }, "lbl2"):AddDropdown({
    Options = {
        "Alice", "AliceWonder", "Bob", "Bobby123",
        "Charlie", "CharlieX", "Dave", "David99",
        "Eve", "Evelyn", "Frank", "Franky",
        "Grace", "Greg", "Henry", "Hugo",
        "Ivy", "Ivan", "Jake", "James",
        "Karen", "Kyle", "Laura", "Leo",
        "Mike", "Mia", "Nina", "Noah",
        "Oscar", "Olivia", "Paul", "Paula",
        "Quinn", "Rachel", "Ryan", "Sara",
        "Tom", "Tina", "Uma", "Victor",
        "Wendy", "Xander", "Yara", "Zoe",
    },
    CurrentOption = {},
    MultipleOptions = true,
    Placeholder = "Type to search...",
    Callback = function(v)
        print("[Multi] Selected:", table.concat(v, ", "))
    end,
}, "drop_multi")

print("[DropdownSearch] Test window loaded! Open dropdowns and type to filter.")
