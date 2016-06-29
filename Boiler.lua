--[[
    Harri Knox's Boiler Calculator
    
    Will eventually do the following:
    -   TPFf Hh -> St       calculate steam produced and time taken
    -   TPF SH  -> f        calculate minimum fuel amount needed to produce an amount of steam
    -   TPF  Hh -> f        calculate fuel required to attain boiling point from H
    -   TPF     -> f/t      calculate fuel consumption rate at max temperature
    -   TPFf    -> h        calculate max heat attained
    -   TP   Hh -> time     calculate time for tank to cool off from given size, pressure, and starting heat
    -     Ff    -> TP       determine most efficient size for maximum steam production
                                (can also be PFf -> T or TFf -> P;
                                uses TPFf -> S with all 12 discrete values for TP (6 sizes * 2 pressures) to get one with max S)
    given (T)ank size, tank (P)ressure, (F)uel type, (f)uel amount, (S)team amount, starting (H)eat, cool down (h)eat, (t)ime
    
    Stages:
    1)  heat up from cool to boiling
    2)  heat up from boiling to max
    3)  duration of max temperature (0 if maxheat not hit)
    4)  cool down from max to boiling
    5)  cool down from boiling to cool
    
    Sizes:
    1 * 1 * 1 = 1
    2 * 2 * 2 = 8
    2 * 2 * 3 = 12
    3 * 3 * 2 = 18
    3 * 3 * 3 = 27
    3 * 3 * 4 = 36
--]]

if not textutils then
    io.stderr:write("\27[1;31mThis version of the Boiler Calculator requires ComputerCraft to run\n\27[0m")
    os.exit(-1)
end

local screensizex, screensizey = term.getSize()
if screensizey < 19 or screensizex < 26 then
    if term.isColor() then
        term.setTextColor(colors.red)
    end
    write("Screen size is too small\n")
    error()
end


local floor = math.floor
local max = math.max
local min = math.min
local maxint = 2 ^ 53
local constrain = function(value, low, high) return max(min(value, high), low) end

local keyup          = keys['up']
local keydown        = keys['down']
local keyleft        = keys['left']
local keyright       = keys['right']
local keyenter       = keys['enter']
local keynumpadenter = 156 -- included because sometimes the numpad enter key is mapped to 156
local keybackspace   = keys['backspace']
local pullevent = os.pullEvent

local setcursorposition = term.setCursorPos
local getcursorposition = term.getCursorPos
local shiftcursorposition = function(deltacolumn, deltarow) local column, row = getcursorposition(); setcursorposition(column + deltacolumn, row + deltarow) end

local stringmatch = string.match
local stringsub = string.sub

local advanced = term.isColor()
local white     = colors.white     -- 0x0001
local orange    = colors.orange    -- 0x0002
local magenta   = colors.magenta   -- 0x0004
local lightblue = colors.lightBlue -- 0x0008
local yellow    = colors.yellow    -- 0x0010
local lime      = colors.lime      -- 0x0020
local pink      = colors.pink      -- 0x0040
local grey      = colors.gray      -- 0x0080
local lightgrey = colors.lightGray -- 0x0100
local cyan      = colors.cyan      -- 0x0200
local purple    = colors.purple    -- 0x0400
local blue      = colors.blue      -- 0x0800
local brown     = colors.brown     -- 0x1000
local green     = colors.green     -- 0x2000
local red       = colors.red       -- 0x4000
local black     = colors.black     -- 0x8000
local setcursorblink = term.setCursorBlink
local settextcolor = advanced and term.setTextColor or function(color) term.setTextColor(color == black and black or white) end
local setbackgroundcolor = advanced and term.setBackgroundColor or function(color) term.setBackgroundColor(color == black and black or white) end
local clear = function() setbackgroundcolor(black) settextcolor(white) setcursorposition(1, 1) term.clear() end
local writewithcolorflip
do
    local previoustextcolor, previousflipped
    writewithcolorflip = function(flipped, textcolor, text)
        if textcolor ~= previoustextcolor or flipped ~= previousflipped then
            settextcolor(flipped and black or textcolor)
            setbackgroundcolor(flipped and textcolor or black)
            previoustextcolor, previousflipped = textcolor, flipped
        end
        write(text)
    end
end


local tanksizes = {1, 8, 12, 18, 27, 36}
local heatvalues = {
    [1] = {
        ["fire_water"]        = 120000,
        ["rocket_fuel"]       = 112000,
        ["blazing_pyrotheum"] =  64000,
        ["fuel"]              =  48000,
        ["hootch"]            =  36000,
        ["liquifacted_coal"]  =  32000,
        ["biofuel"]           =  16000,
        ["ethanol"]           =  16000,
        ["creosote_oil"]      =   4800,
    },
    [2] = {
        ["coal_coke_block"]           = 32000,
        ["pyrotheum_dust"]            = 24000,
        ["biofuel_bucket_mfr"]        = 22500, -- included because MFR gives biofuel a furnace burn time; more efficient in solid-fueled boilers than liquid (22.5 vs 16 per bucket)
        ["coal_block"]                = 16000,
        ["bituminous_peat"]           =  4200,
        ["sugar_charcoal_block"]      =  4000,
        ["coal_coke"]                 =  3200,
        ["peat"]                      =  2000,
        ["charcoal"]                  =  1600,
        ["coal"]                      =  1600,
        ["blaze_rod"]                 =  1000,
        ["lava_container"]            =  1000, -- 1000 because 1 bucket provides 1000 heat units, so 1.625 buckets will provide 1625 heat units
        ["pile_of_ashes"]             =   400,
        ["sugar_charcoal"]            =   400,
        ["rubber_bar"]                =   300,
        ["wood_block"]                =   300,
        ["refined_firestone"]         =   250,
        ["wood_tool"]                 =   200,
        ["wood_slab_vanilla"]         =   150,
        ["rubber_sapling_mfr"]        =   130,
        ["cracked_firestone"]         =   100,
        ["rubber_tree_sapling_ic2"]   =    80,
        ["cactus"]                    =    50,
        ["raw_rubber"]                =    30,
        ["dry_rubber_leaves_mfr"]     =     8,
        ["rubber_leaves_mfr"]         =     4,
    }
}
local fueltypes
do
    local getkeyssorted = function(source)
        local keys, index = {}, 1
        for key in pairs(source) do
            keys[index], index = key, index + 1
        end
        table.sort(keys)
        return keys
    end
    
    fueltypes = {
        [1] = getkeyssorted(heatvalues[1]),
        [2] = getkeyssorted(heatvalues[2])
    }
end

local writetitle = function()
    writewithcolorflip(false, orange, "Harri Knox's Boiler Simulator/Calculator\n\n")
end

local getoperationselection = function()
    local runloop = true
    local previousselection = 0
    local selection = 1
    local selectionsypositions = {}
    local selections = {
        "1) total steam produced\n",
        "2) * fuel consumption rate\n",
        "3) * min fuel needed for steam\n",
        "4) * min fuel needed for heat\n",
        "5) * most efficient boiler size\n"
    }
    
    while runloop do
        local event, key, y
        if selection ~= previousselection then
            previousselection = selection
            
            clear()
            writetitle()
            writewithcolorflip(false, yellow, "What you would like to calculate: (asterisked operations are not yet implemented)\n\n")
            
            for i = 1, #selections do
                if not selectionsypositions[i] then
                    _, selectionsypositions[i] = getcursorposition()
                end
                
                writewithcolorflip(i == selection, lime, selections[i])
            end
            if not selectionsypositions[#selectionsypositions + 1] then
                _, selectionsypositions[#selectionsypositions + 1] = getcursorposition()
            end
            
            writewithcolorflip(selection == 6, red, "\nQuit")
        end
        
        event, key, _, y = pullevent()
        if event == "key" then
            if key == keydown then
                if selection < 6 then
                    selection = selection + 1
                end
            elseif key == keyup then
                if selection > 1 then
                    selection = selection - 1
                end
            elseif key == keyenter or key == keynumpadenter then
                runloop = false
            end
        elseif event == "char" then
            local num = tonumber(key)
            if num then
                if num >= 1 and num <= #selections then
                    selection = num
                    if selection == previousselection then
                        runloop = false
                    end
                end
            elseif key == "q" then
                selection = 6
                runloop = false
            end
        elseif event == "mouse_click" then
            if y >= selectionsypositions[1] and y < selectionsypositions[6] then
                for i = 1, #selections do
                    if y >= selectionsypositions[i] and y < selectionsypositions[i + 1] then
                        selection = i
                        if selection == previousselection then
                            runloop = false
                        end
                        break
                    end
                end
            elseif y == selectionsypositions[6] + 1 then
                selection = 6
                if selection == previousselection then
                    runloop = false
                end
            end
        end
    end
    return selection
end


local totalsteamproducedoptionsscreen
do
    local formatfuelamount = function(fuelamount)
        local fuelamountstring = tostring(fuelamount)
        if #fuelamountstring > screensizex - 3 then
            return "..." .. stringsub(fuelamountstring, -screensizex + 6, -1)
        end
        return fuelamountstring
    end
    
    totalsteamproducedoptionsscreen = function()
        local tankpressure = 1
        local tanksize = 1
        local boilertype = 1
        local fueltype = 1
        local fuelamount = 1000 -- to be bigint
        local fuelamountstring = tostring(fuelamount)
        local startingheat = 20
        local cooldownheat = 20
        local maxfueltype = 10
        
        local previoustankpressure = 0
        local previoustanksize = 0
        local previousboilertype = 0
        local previousfueltype = 0
        local maxheat = 500
        
        local runloop = true
        local selection = 1
        local previousselection = 0
        local topofsettingsy
        local fuelamountcursorx
        local startingheatcursorx
        local cooldownheatcursorx
        
        while runloop do
            local event, key, x, y
            if selection ~= previousselection or tankpressure ~= previoustankpressure or tanksize ~= previoustanksize or boilertype ~= previousboilertype or fueltype ~= previousfueltype then
                previousselection = selection
                previoustankpressure = tankpressure
                previoustanksize = tanksize
                previousboilertype = boilertype
                previousfueltype = fueltype
                maxfueltype = #(fueltypes[boilertype])
                startingheat = constrain(startingheat, 20, maxheat)
                cooldownheat = constrain(cooldownheat, 20, maxheat)
                fuelamount = constrain(fuelamount, 1, maxint)
                
                clear()
                writetitle()
                writewithcolorflip(false, lime, "Total Steam Produced\n\n")
                
                if not topofsettingsy then
                    _, topofsettingsy = getcursorposition()
                end
                
                writewithcolorflip(selection == 1, magenta, "tank pressure")
                writewithcolorflip(false, magenta, ": ")
                writewithcolorflip(tankpressure == 1, lightblue, "low")
                writewithcolorflip(false, lightblue, " ")
                writewithcolorflip(tankpressure == 2, lightblue, "high\n")
                
                writewithcolorflip(selection == 2, magenta, "tank size")
                writewithcolorflip(false, magenta, ":")
                for i = 1, #tanksizes do
                    writewithcolorflip(false, lightblue, " ")
                    writewithcolorflip(i == tanksize, lightblue, tostring(tanksizes[i]))
                end
                
                writewithcolorflip(selection == 3, magenta, "\nboiler type")
                writewithcolorflip(false, magenta, ": ")
                writewithcolorflip(boilertype == 1, lightblue, "liquid")
                writewithcolorflip(false, lightblue, " ")
                writewithcolorflip(boilertype == 2, lightblue, "solid\n")
                
                writewithcolorflip(selection == 4, magenta, "fuel type")
                writewithcolorflip(false, magenta, ": ")
                writewithcolorflip(false, lightblue, fueltype == 1 and "  -" or "<<-")
                write(fueltype == maxfueltype and "\n  " or ">>\n  ")
                write(fueltypes[boilertype][fueltype])
                write('\n')
                
                writewithcolorflip(selection == 5, magenta, "fuel amount")
                writewithcolorflip(false, magenta, ": ")
                writewithcolorflip(false, lightblue, boilertype == 1 and "mB" or "blocks/items")
                write('\n  ')
                fuelamountcursorx, _ = getcursorposition()
                write(fuelamountstring)
                
                writewithcolorflip(selection == 6, magenta, "\nstarting heat")
                writewithcolorflip(false, magenta, ": ")
                startingheatcursorx, _ = getcursorposition()
                writewithcolorflip(false, lightblue, tostring(startingheat))
                
                writewithcolorflip(selection == 7, magenta, "\ncool-down heat")
                writewithcolorflip(false, magenta, ": ")
                cooldownheatcursorx, _ = getcursorposition()
                writewithcolorflip(false, lightblue, tostring(cooldownheat))
                
                writewithcolorflip(selection == 8, lime, "\n\nSimulate\n")
                writewithcolorflip(selection == 9, yellow, "Previous\n")
                writewithcolorflip(selection == 10, red, "Quit")
                setcursorposition(0, 0)
                if selection < 5 or selection > 7 then
                    setcursorblink(false)
                else
                    if selection == 5 then
                        setcursorposition(fuelamountcursorx + #fuelamountstring, topofsettingsy + 6)
                    elseif selection == 6 then
                        setcursorposition(startingheatcursorx + #tostring(startingheat), topofsettingsy + 7)
                    elseif selection == 7 then
                        setcursorposition(cooldownheatcursorx + #tostring(cooldownheat), topofsettingsy + 8)
                    end
                    settextcolor(lightblue)
                    setcursorblink(true)
                end
            end
            
            event, key, x, y = pullevent()
            if event == "key" then
                if key == keyup then
                    if selection > 1 then
                        selection = selection - 1
                    end
                elseif key == keydown then
                    if selection < 10 then
                        selection = selection + 1
                    end
                elseif key == keyright then
                    if selection == 1 and tankpressure == 1 then
                        tankpressure = 2
                        maxheat = 1000
                    elseif selection == 2 and tanksize < 6 then
                        tanksize = tanksize + 1
                    elseif selection == 3 and boilertype == 1 then
                        boilertype = 2
                        fueltype = 1
                    elseif selection == 4 and fueltype < maxfueltype then
                        fueltype = fueltype + 1
                    end
                elseif key == keyleft then
                    if selection == 1 and tankpressure == 2 then
                        tankpressure = 1
                        maxheat = 500
                    elseif selection == 2 and tanksize > 1 then
                        tanksize = tanksize - 1
                    elseif selection == 3 and boilertype == 2 then
                        boilertype = 1
                        fueltype = 1
                    elseif selection == 4 and fueltype > 1 then
                        fueltype = fueltype - 1
                    end
                elseif key == keyenter or key == keynumpadenter then
                    if selection >= 8 then
                        runloop = false
                    else
                        selection = 8
                    end
                elseif key == keybackspace then
                    if selection == 5 then
                        fuelamount = floor(fuelamount / 10)
                        fuelamountstring = formatfuelamount(fuelamount)
                        setcursorposition(fuelamountcursorx, topofsettingsy + 6)
                        writewithcolorflip(false, lightblue, fuelamountstring)
                        write(' ')
                        shiftcursorposition(-1, 0)
                    elseif selection == 6 then
                        startingheat = floor(startingheat / 10)
                        setcursorposition(startingheatcursorx, topofsettingsy + 7)
                        writewithcolorflip(false, lightblue, tostring(startingheat))
                        write(' ')
                        shiftcursorposition(-1, 0)
                    elseif selection == 7 then
                        cooldownheat = floor(cooldownheat / 10)
                        setcursorposition(cooldownheatcursorx, topofsettingsy + 8)
                        writewithcolorflip(false, lightblue, tostring(cooldownheat))
                        write(' ')
                        shiftcursorposition(-1, 0)
                    end
                end
            elseif event == "char" then
                local num = tonumber(key)
                if num then
                    if selection == 5 then
                        fuelamount = fuelamount * 10 + num
                        fuelamountstring = formatfuelamount(fuelamount)
                        setcursorposition(fuelamountcursorx, topofsettingsy + 6)
                        writewithcolorflip(false, lightblue, fuelamountstring)
                    elseif selection == 6 then
                        startingheat = startingheat * 10 + num
                        if startingheat < 10 then
                            shiftcursorposition(-1, 0)
                        end
                        writewithcolorflip(false, lightblue, key)
                    elseif selection == 7 then
                        cooldownheat = cooldownheat * 10 + num
                        if cooldownheat < 10 then
                            shiftcursorposition(-1, 0)
                        end
                        writewithcolorflip(false, lightblue, key)
                    end
                elseif key == 'q' then
                    runloop = false
                    selection = 10
                end
            elseif event == "mouse_click" then
                local relativeyposition = y - topofsettingsy + 1
                if relativeyposition >= 1 and relativeyposition <= 9 then
                    if relativeyposition <= 4 then
                        selection = relativeyposition
                    elseif relativeyposition <= 6 then
                        selection = relativeyposition - 1
                    else
                        selection = relativeyposition - 2
                    end
                    
                    if selection == 1 then
                        if x >= 16 and x <= 18 then
                            tankpressure = 1
                            maxheat = 500
                        elseif x >= 20 and x <= 23 then
                            tankpressure = 2
                            maxheat = 1000
                        end
                    elseif selection == 2 then
                        if x == 12 then -- Perhaps a more efficient way to do this, but for now I care not
                            tanksize = 1
                        elseif x == 14 then
                            tanksize = 2
                        elseif x == 16 or x == 17 then
                            tanksize = 3
                        elseif x == 19 or x == 20 then
                            tanksize = 4
                        elseif x == 22 or x == 23 then
                            tanksize = 5
                        elseif x == 25 or x == 26 then
                            tanksize = 6
                        end
                    elseif selection == 3 then
                        if x >= 14 and x <= 19 then
                            boilertype = 1
                            fueltype = 1
                        elseif x >= 21 and x <= 25 then
                            boilertype = 2
                            fueltype = 1
                        end
                    elseif relativeyposition == 4 then
                        if (x == 12 or x == 13) and fueltype > 1 then
                            fueltype = fueltype - 1
                        elseif (x == 15 or x == 16) and fueltype < maxfueltype then
                            fueltype = fueltype + 1
                        end
                    end
                elseif relativeyposition >= 11 and relativeyposition <= 13 then
                    selection = relativeyposition - 3
                    if selection == previousselection then
                        runloop = false
                    end
                end
            end
        end
        
        return selection, {tankpressure = tankpressure, tanksize = tanksize, boilertype = boilertype, fueltype = fueltype, fuelamount = fuelamount, startingheat = startingheat, cooldownheat = cooldownheat}
    end
end

local calculatesteamproduced

local calculatesteamproducedscreen = function(state)
    local runloop = true
    local previousselection = 0
    local selection = 1
    local topofbuttonsyposition
    
    local completedstate = calculatesteamproduced(state)
    
    local steamamount = completedstate.steamamount
    local maxheatattained = completedstate.maxheatattained
    local totalticks = completedstate.totalticks
    
    while runloop do
        local event, key, y
        if previousselection ~= selection then
            previousselection = selection
            
            clear()
            writetitle()
            
            writewithcolorflip(false, lime, "Boiler Calculation Results\n\n")
            writewithcolorflip(false, pink, "Steam: ")
            writewithcolorflip(false, lightblue, steamamount)
            writewithcolorflip(false, lightblue, " mB\n")
            writewithcolorflip(false, pink, "Max heat: ")
            writewithcolorflip(false, lightblue, maxheatattained)
            writewithcolorflip(false, lightblue, "\n")
            writewithcolorflip(false, pink, "Time taken: ")
            writewithcolorflip(false, lightblue, totalticks)
            writewithcolorflip(false, lightblue, " ticks\n\n")
            
            if not topofbuttonsyposition then
                _, topofbuttonsyposition = getcursorposition()
            end
            writewithcolorflip(selection == 1, yellow, "Previous\n")
            writewithcolorflip(selection == 2, red, "Quit")
        end
        
        event, key, _, y = pullevent()
        if event == "key" then
            if key == keyup then
                selection = 1
            elseif key == keydown then
                selection = 2
            elseif key == keyenter or key == keynumpadenter then
                runloop = false
            end
        elseif event == "char" then
            if key == "q" then
                selection = 2
                runloop = false
            end
        elseif event == "mouse_click" then
            if y == topofbuttonsyposition or y == topofbuttonsyposition + 1 then
                selection = y - topofbuttonsyposition + 1
                if selection == previousselection then
                    runloop = false
                end
            end
        end
    end
    
    return selection
end

local processcontroller = function()
    local process = 1
    local run = true
    local selection, state
    
    while run do
        sleep(0)
        if process == 1 then
            selection = getoperationselection()
            
            if selection == 6 then
                process = 0
            elseif selection >= 1 and selection < 6 then
                process = selection + 1
            else
                process = -1
            end
        elseif process == 2 then
            selection, state = totalsteamproducedoptionsscreen()
            
            if selection == 8 then
                process = 20
            elseif selection == 9 then
                process = 1
            elseif selection == 10 then
                process = 0
            else
                process = -1
            end
        elseif process == 20 then
            selection = calculatesteamproducedscreen(state)
            
            if selection == 1 then
                process = 2
            elseif selection == 2 then
                process = 0
            else
                process = -1
            end
        elseif process >= 3 and process <= 8 then
            process = -2
        elseif process == 0 then
            clear()
            run = false
        elseif process == -1 then
            clear()
            writewithcolorflip(false, red, "Unusual unhandled exception occurred. Sorry.\n")
            run = false
        elseif process == -2 then
            clear()
            writewithcolorflip(false, red, "Operation not supported. Sorry.\n")
            run = false
        else
            process = -1
        end
    end
end

processcontroller()
