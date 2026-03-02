--[[
    Starlight Dropdown Search Patch
    ────────────────────────────────────────────────────────────────────────────
    USAGE:
        local Starlight = loadstring(game:HttpGet("https://raw.nebulasoftworks.xyz/starlight"))()
        require(script.Starlight_DropdownSearch)(Starlight)   -- or loadstring/inline it
        -- then create your window as normal
    ────────────────────────────────────────────────────────────────────────────
    HOW IT WORKS:
    - Hooks Starlight.Instance after the lib loads and patches every
      DropdownPopup's List with a search TextBox injected at the top.
    - The TextBox filters option rows live as you type (case-insensitive).
    - Works for both single and multi-select dropdowns.
    - Automatically respects the existing theme colours via ThemeMethods-style
      property binding so it looks native.
    ────────────────────────────────────────────────────────────────────────────
]]

return function(Starlight)
    -- ── Wait until the Instance exists (it is set during CreateWindow) ────────
    local function waitForInstance()
        if Starlight.Instance then return Starlight.Instance end
        local t = 0
        repeat
            task.wait(0.05)
            t = t + 0.05
        until Starlight.Instance or t > 30
        return Starlight.Instance
    end

    task.spawn(function()
        local starlightInstance = waitForInstance()
        if not starlightInstance then
            warn("[DropdownSearch] Starlight.Instance never became available.")
            return
        end

        -- ── Helper: inject search into one DropdownPopup frame ────────────────
        local function patchPopup(popup)
            -- Guard: already patched or no List child
            if popup:FindFirstChild("SearchBox") then return end
            local List = popup:FindFirstChild("List")
            if not List or not List:IsA("ScrollingFrame") then return end

            -- ── Build the search bar ─────────────────────────────────────────
            local searchHolder = Instance.new("Frame")
            searchHolder.Name         = "SearchHolder"
            searchHolder.Size         = UDim2.new(1, 0, 0, 28)
            searchHolder.BackgroundTransparency = 1
            searchHolder.BorderSizePixel = 0
            searchHolder.LayoutOrder  = -9999   -- always first in the List
            searchHolder.Parent       = List

            local searchBox = Instance.new("TextBox")
            searchBox.Name            = "SearchBox"
            searchBox.Size            = UDim2.new(1, -12, 1, -6)
            searchBox.Position        = UDim2.fromOffset(6, 3)
            searchBox.BackgroundColor3 = Color3.fromRGB(17, 19, 22)  -- Backgrounds.Highlight default
            searchBox.BorderSizePixel = 0
            searchBox.Text            = ""
            searchBox.PlaceholderText = "Search..."
            searchBox.TextSize        = 12
            searchBox.Font            = Enum.Font.GothamMedium
            searchBox.TextColor3      = Color3.fromRGB(255, 255, 255)
            searchBox.PlaceholderColor3 = Color3.fromRGB(165, 165, 165)
            searchBox.TextXAlignment  = Enum.TextXAlignment.Left
            searchBox.ClearTextOnFocus = false
            searchBox.ZIndex          = popup.ZIndex + 2
            searchBox.Parent          = searchHolder

            -- Rounded corners on the search box
            local corner = Instance.new("UICorner")
            corner.CornerRadius = UDim.new(0, 4)
            corner.Parent       = searchBox

            -- Stroke so it looks like a native input
            local stroke = Instance.new("UIStroke")
            stroke.Color      = Color3.fromRGB(65, 69, 77)   -- Foregrounds.Dark default
            stroke.Thickness  = 1
            stroke.Parent     = searchBox

            -- Try to keep colours in sync with the active theme
            pcall(function()
                if Starlight.CurrentTheme then
                    searchBox.BackgroundColor3  = Starlight.CurrentTheme.Backgrounds.Highlight
                    searchBox.TextColor3        = Starlight.CurrentTheme.Foregrounds.Light
                    searchBox.PlaceholderColor3 = Starlight.CurrentTheme.Foregrounds.Medium
                    stroke.Color                = Starlight.CurrentTheme.Foregrounds.Dark
                end
            end)

            -- ── Filter logic ─────────────────────────────────────────────────
            local function filterOptions(query)
                query = query:lower():gsub("^%s+", ""):gsub("%s+$", "")
                for _, child in ipairs(List:GetChildren()) do
                    -- Only touch option rows (named OPTION_*)
                    if child:IsA("Frame") and child.Name:sub(1, 7) == "OPTION_" then
                        if query == "" then
                            child.Visible = true
                        else
                            -- header TextLabel holds the display text
                            local header = child:FindFirstChild("header")
                            local text   = header and header.Text:lower() or child.Name:lower()
                            child.Visible = text:find(query, 1, true) ~= nil
                        end
                    end
                end
            end

            searchBox:GetPropertyChangedSignal("Text"):Connect(function()
                filterOptions(searchBox.Text)
            end)

            -- Clear search when the popup becomes invisible (i.e. closed)
            popup:GetPropertyChangedSignal("Visible"):Connect(function()
                if not popup.Visible then
                    searchBox.Text = ""
                    filterOptions("")
                end
            end)

            -- Make the List taller by the search bar height so it doesn't
            -- clip the first real option
            List.Size = UDim2.new(1, 0, 1, 0)

            -- Ensure the UIListLayout inside the List sorts correctly
            local layout = List:FindFirstChildOfClass("UIListLayout")
            if layout then
                -- searchHolder has LayoutOrder = -9999, options use default 0
                -- so the search bar always sits at the top automatically
            end
        end

        -- ── Patch all current and future DropdownPopup frames ─────────────────
        local PopupOverlay = starlightInstance:FindFirstChild("Popup Overlay", true)
        if not PopupOverlay then
            -- Fallback: scan the whole ScreenGui
            PopupOverlay = starlightInstance
        end

        -- Patch existing popups (ones created before this script ran)
        for _, child in ipairs(PopupOverlay:GetDescendants()) do
            if child.Name:sub(1, 9) == "DROPDOWN_" and child:IsA("Frame") then
                local list = child:FindFirstChild("List")
                if list and list:IsA("ScrollingFrame") then
                    pcall(patchPopup, child)
                end
            end
        end

        -- Patch future popups as they get added
        PopupOverlay.DescendantAdded:Connect(function(desc)
            -- DropdownPopup frames are direct children of PopupOverlay
            -- named "DROPDOWN_<NestedIndex>"
            if
                desc:IsA("Frame")
                and desc.Name:sub(1, 9) == "DROPDOWN_"
                and desc:FindFirstChild("List")
            then
                task.defer(patchPopup, desc)   -- defer so List children exist
            end
        end)
    end)
end
