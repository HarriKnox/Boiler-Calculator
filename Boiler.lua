--[[
    Harri Knox's Boiler Calculator
    
    Will eventually do the following:
    -   TPFf Hh -> SMt       calculate steam produced and time taken
    -   TPF SH  -> f        calculate minimum fuel amount needed to produce an amount of steam
    -   TPF  Hh -> f        calculate fuel required to attain boiling point from H
    -   TPF     -> f/t      calculate fuel consumption rate at max temperature
    -   TP   Hh -> time     calculate time for tank to cool off from given size, pressure, and starting heat
    -     Ff    -> TP       determine most efficient size for maximum steam production
                                (can also be PFf -> T or TFf -> P;
                                uses TPFf -> S with all 12 discrete values for TP (6 sizes * 2 pressures) to get one with max S)
    given (T)ank size, tank (P)ressure, (F)uel type, (f)uel amount, (S)team amount, starting (H)eat, cool down (h)eat, (M)ax heat, (t)ime
    
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
    
    TODO:
    Documentation
    Refactorization (DRY-ification)
    BigIntegers and BigRatios
    About page
    Display clean-up
--]]

if not textutils then
    io.stderr:write("\27[1;31mThis version of the Boiler Calculator requires ComputerCraft to run\n\27[0m")
    os.exit(-1)
end

local getscreensize = term.getSize
do
    local screensizex, screensizey = getscreensize()
    if screensizey < 18 or screensizex < 26 then
        if term.isColor() then
            term.setTextColor(colors.red)
        end
        write("Screen size is too small\n")
        error()
    end
end


local floor = math.floor
local ceil = math.ceil
local round = function(x) return x < 0 and ceil(x - 0.5) or floor(x + 0.5) end
local max = math.max
local min = math.min
local maxint = math.maxinteger or 2 ^ 53
local constrain = function(value, low, high)
    if high < low then
        low, high = high, low
    end
    return max(min(value, high), low)
end
local log10 = math.log10
if not log10 then
    local mathlog10 = math.log(10)
    log10 = function(x)
        return math.log(x) / mathlog10
    end
end

local keyup          = keys['up']
local keydown        = keys['down']
local keyleft        = keys['left']
local keyright       = keys['right']
local keyenter       = keys['enter']
local keynumpadenter = 156 -- included because sometimes the numpad enter key is mapped to 156
local keybackspace   = keys['backspace']
local scrollup       = -1
local scrolldown     = 1
local pullevent = os.pullEvent

local setcursorposition = term.setCursorPos
local getcursorposition = term.getCursorPos
local shiftcursorposition = function(deltacolumn, deltarow)
    local column, row = getcursorposition()
    setcursorposition(column + deltacolumn, row + deltarow)
end

local stringmatch = string.match
local stringsub = string.sub
local stringformat = string.format

local tableinsert = table.insert
local tablesort = table.sort

local colorwhite     = colors.white     -- 0x0001
local colororange    = colors.orange    -- 0x0002
local colormagenta   = colors.magenta   -- 0x0004
local colorlightblue = colors.lightBlue -- 0x0008
local coloryellow    = colors.yellow    -- 0x0010
local colorlime      = colors.lime      -- 0x0020
local colorpink      = colors.pink      -- 0x0040
local colorgrey      = colors.gray      -- 0x0080
local colorlightgrey = colors.lightGray -- 0x0100
local colorcyan      = colors.cyan      -- 0x0200
local colorpurple    = colors.purple    -- 0x0400
local colorblue      = colors.blue      -- 0x0800
local colorbrown     = colors.brown     -- 0x1000
local colorgreen     = colors.green     -- 0x2000
local colorred       = colors.red       -- 0x4000
local colorblack     = colors.black     -- 0x8000
local setcursorblink = term.setCursorBlink
local settextcolor, setbackgroundcolor, clear, writewithcolorflip
do
    local previoustextcolor, previousbackgroundcolor
    local advanced = term.isColor()
    
    settextcolor = function(color)
        if not advanced then
            color = color == colorblack and colorblack or colorwhite
        end
        if color ~= previoustextcolor then
            previoustextcolor = color
            term.setTextColor(color)
        end
    end
    
    setbackgroundcolor = function(color)
        if not advanced then
            color = color == colorblack and colorblack or colorwhite
        end
        if color ~= previousbackgroundcolor then
            previousbackgroundcolor = color
            term.setBackgroundColor(color)
        end
    end
    
    clear = function()
        setbackgroundcolor(colorblack)
        settextcolor(colorwhite)
        setcursorposition(1, 1)
        term.clear()
    end
    
    writewithcolorflip = function(flipped, textcolor, text)
        settextcolor(flipped and colorblack or textcolor)
        setbackgroundcolor(flipped and textcolor or colorblack)
        write(text)
    end
end

local writetitle = function()
    writewithcolorflip(false, colororange, "H Knox's Boiler Calculator\n\n")
end

local formatfuelamount = function(fuelamount)
    local fuelamountstring = tostring(fuelamount)
    local screensizex
    screensizex, _ = getscreensize()
    if #fuelamountstring > screensizex - 3 then
        return "..." .. stringsub(fuelamountstring, -screensizex + 6, -1)
    end
    return fuelamountstring
end


local tanksizes = {1, 8, 12, 18, 27, 36}
local heatvalues = {
    [1] = {
        ['fire_water']        = 120000,
        ['rocket_fuel']       = 112000,
        ['blazing_pyrotheum'] =  64000,
        ['fuel']              =  48000,
        ['hootch']            =  36000,
        ['liquifacted_coal']  =  32000,
        ['biofuel']           =  16000,
        ['ethanol']           =  16000,
        ['creosote_oil']      =   4800,
    },
    [2] = {
        ['coal_coke_block']           = 32000,
        ['pyrotheum_dust']            = 24000,
        ['biofuel_bucket_mfr']        = 22500, -- included because MFR gives biofuel a furnace burn time; more efficient in solid-fueled boilers than liquid (22.5 vs 16 per bucket)
        ['coal_block']                = 16000,
        ['bituminous_peat']           =  4200,
        ['sugar_charcoal_block']      =  4000,
        ['coal_coke']                 =  3200,
        ['peat']                      =  2000,
        ['charcoal']                  =  1600,
        ['coal']                      =  1600,
        ['blaze_rod']                 =  1000,
        ['lava_container']            =  1000, -- 1000 because 1 bucket provides 1000 heat units, so 1.625 buckets will provide 1625 heat units
        ['pile_of_ashes']             =   400,
        ['sugar_charcoal']            =   400,
        ['rubber_bar']                =   300,
        ['wood_block']                =   300,
        ['refined_firestone']         =   250,
        ['wood_tool']                 =   200,
        ['wood_slab_vanilla']         =   150,
        ['rubber_sapling_mfr']        =   130,
        ['cracked_firestone']         =   100,
        ['rubber_tree_sapling_ic2']   =    80,
        ['cactus']                    =    50,
        ['raw_rubber']                =    30,
        ['dry_rubber_leaves_mfr']     =     8,
        ['rubber_leaves_mfr']         =     4,
    }
}
local fueltypes
do
    local getkeyssorted = function(source)
        local keys, index = {}, 1
        for key in pairs(source) do
            keys[index], index = key, index + 1
        end
        tablesort(keys)
        return keys
    end
    
    fueltypes = {
        [1] = getkeyssorted(heatvalues[1]),
        [2] = getkeyssorted(heatvalues[2])
    }
end

local sortsteamamounts = function(a, b)
    return a.steamamount > b.steamamount
end

local teststateparameters = function(state)
    local tankpressure = state.tankpressure
    local tanksize = state.tanksize
    local boilertype = state.boilertype
    local fueltype = state.fueltype
    local fuelamount = state.fuelamount
    local startingheat = state.startingheat
    local cooldownheat = state.cooldownheat
    
    local validtanksize = false
    local maxheat = tankpressure == 1 and 500 or 1000
    
    if not (tankpressure == 1 or tankpressure == 2) then
        error("tank pressure not valid: " .. tankpressure, 3)
    end
    
    if not (tanksize >= 1 and tanksize <= 6) then
        error("tank size not valid, must be between 1 and 6: " .. tanksize, 3)
    end
    
    if fueltypes[boilertype] == nil then
        error("boiler type not valid, must be 1 or 2: " .. boilertype, 3)
    end
    
    if fueltypes[boilertype][fueltype] == nil then
        error("fuel type not valid, must be between 1 and " .. #fueltypes[boilertype] .. ": " .. fueltype, 3)
    end
    
    if not (fuelamount >= 1 and fuelamount <= maxint) or fuelamount % 1 ~= 0 then
        error("fuel amount not valid, must be an integer, positive, and less than the maxint: " .. fuelamount, 3)
    end
    
    if not (startingheat >= 20 and startingheat <= maxheat) then
        error("starting heat not valid, must be between 20 and " .. maxheat .. ": " .. startingheat, 3)
    end
    
    if not (cooldownheat >= 20 and cooldownheat <= maxheat) then
        error("cool-down heat not valid, must be between 20 and " .. maxheat .. ": " .. cooldownheat, 3)
    end
end

-- Fuel per Cycle
-- Derived from original function in the source code as follows:
-- 
-- public double getFuelPerCycle {
--   double fuel = Steam.FUEL_PER_BOILER_CYCLE;
--   fuel -= numTanks * Steam.FUEL_PER_BOILER_CYCLE * 0.0125F;
--   fuel += Steam.FUEL_HEAT_INEFFICIENCY * getHeatLevel();
--   fuel += Steam.FUEL_PRESSURE_INEFFICIENCY * (getMaxHeat() / Steam.MAX_HEAT_HIGH);
--   fuel *= numTanks;
--   fuel *= efficiencyModifier;
--   fuel *= RailcraftConfig.fuelPerSteamMultiplier();
--   return fuel;
-- }
-- where
--   Steam.FUEL_PER_BOILER_CYCLE = 8
--   Steam.FUEL_HEAT_INEFFICIENCY = 0.8
--   Steam.FUEL_PRESSURE_INEFFICIENCY = 4
--   Steam.MAX_HEAT_HIGH = 1000
--   efficiencyModifier = 1
--   RailcraftConfig.fuelPerSteamMultiplier() = 1 in default settings
-- and as determined at runtime
--   numTanks = 1, 8, 12, 18, 27 or 36
--   getMaxHeat = 500 or 1000 for low, high pressure tanks respectively
--   getHeatLevel = heat / getMaxHeat
-- 
-- Inserting these values yields
-- fuel = (8 - (numTanks * 8 * 0.0125) + (0.8 * heat / maxHeat) + (4 * maxHeat / 1000)) * numTanks * 1 * 1
-- 
-- Doing arithmetic to create a linear function of heat with a coefficient and offset returns
-- fuel = (numtanks * 0.8 / maxHeat) * heat + (8 - (numTanks * 0.1) + (4 * maxHeat / 1000)) * numTanks
local getfuelneededpercyclecoefficient = function(maxheat, numberoftanks)
    return numberoftanks * 0.8 / maxheat
end
local getfuelneededpercycleoffset = function(maxheat, numberoftanks)
    return (8 - (numberoftanks * 0.1) + (4 * maxheat / 1000)) * numberoftanks
end
local getfuelneededpercyclemaximum = function(maxheat, numberoftanks)
    return (numberoftanks * 0.8) + getfuelneededpercycleoffset(maxheat, numberoftanks)
end



local calculatesteamproduced = function(state)
    teststateparameters(state)
    
    local tankpressure = state.tankpressure
    local tanksize = state.tanksize
    local boilertype = state.boilertype
    local fueltype = state.fueltype
    local fuelamount = state.fuelamount
    local startingheat = state.startingheat
    local cooldownheat = state.cooldownheat
    
    local heatvalue = heatvalues[boilertype][fueltypes[boilertype][fueltype]]
    local numberoftanks = tanksizes[tanksize]
    local fuelburning = 0
    local isburning = true
    local partialconversions = 0
    local watercost = 0
    
    -- relative constants
    local maxheat = tankpressure == 1 and 500 or 1000
    local heat = startingheat
    
    
    local fuelneededpercyclecoefficient = getfuelneededpercyclecoefficient(maxheat, numberoftanks)
    local fuelneededpercycleoffset = getfuelneededpercycleoffset(maxheat, numberoftanks)
    local fuelneededpercyclemaximum = getfuelneededpercyclemaximum(maxheat, numberoftanks)
    local fuelneededpercycle
    --local getfuelpercycle = function(heat) return fuelpercyclecoefficient * heat + fuelpercycleoffset end
    
    
    local heatstep = stringmatch(fueltypes[boilertype][fueltype], 'firestone') and 1.5 or 0.05
    local increasingheatchangecoefficient = -3 * heatstep / (maxheat * numberoftanks)
    local increasingheatchangeoffset = 4 * heatstep / numberoftanks
    local decreasingheatchangecoefficient = 0.15 / (maxheat * numberoftanks) -- 3 * 0.05 / (maxheat * numberoftanks)
    local decreasingheatchangeoffset = 0.05 / numberoftanks
    
    
    local tickspercycle = tankpressure == 1 and 16 or 8 -- 8 * 1000 / maxheat
    local tickspercycleremaining = 0
    local cycles
    
    
    local steamamount = 0 -- to be bigint
    local maxheatattained = 0
    local totalticks = 0 -- to be bigint
    
    -- heat-up
    while isburning and heat < maxheat do
        totalticks = totalticks + 1
        tickspercycleremaining = tickspercycleremaining - 1
        if tickspercycleremaining <= 0 then
            tickspercycleremaining = tickspercycle
            fuelneededpercycle = (fuelneededpercyclecoefficient * heat) + fuelneededpercycleoffset
            while fuelburning < fuelneededpercycle and fuelamount > 0 do
                if boilertype == 1 then -- liquid-fueled firebox
                    if fuelamount >= 1000 then
                        fuelburning = fuelburning + heatvalue
                        fuelamount = fuelamount - 1000
                    else
                        fuelburning = fuelburning + heatvalue * fuelamount / 1000
                        fuelamount = 0
                    end
                else -- solid-fueled firebox
                    fuelburning = fuelburning + heatvalue
                    fuelamount = fuelamount - 1
                end
            end
            
            isburning = fuelburning >= fuelneededpercycle
            if isburning then
                fuelburning = fuelburning - fuelneededpercycle
            end
            
            if heat >= 100 then
                partialconversions = partialconversions + (numberoftanks * heat / maxheat)
                watercost = floor(partialconversions)
                partialconversions = partialconversions - watercost
                steamamount = steamamount + (160 * watercost)
            end
        end
        
        if isburning then
            heat = heat + increasingheatchangecoefficient * heat + increasingheatchangeoffset
        else
            heat = heat - decreasingheatchangecoefficient * heat - decreasingheatchangeoffset
        end
    end
    
    if heat > maxheat then
        heat = maxheat
    end
    
    maxheatattained = heat
    
    if isburning then -- at max temp
        if boilertype == 1 then -- liquid-fueled boiler
            fuelburning = fuelburning + heatvalue * fuelamount / 1000
        else
            fuelburning = fuelburning + heatvalue * fuelamount
        end
        cycles = floor(fuelburning / fuelneededpercyclemaximum)
        fuelburning = fuelburning % fuelneededpercyclemaximum
        watercost = cycles * numberoftanks
        steamamount = steamamount + (160 * watercost)
        fuelamount = 0
        totalticks = totalticks + tickspercycleremaining - 1 + (cycles * tickspercycle)
        tickspercycleremaining = 0
    end
    
    isburning = false
    
    while heat > cooldownheat do
        totalticks = totalticks + 1
        tickspercycleremaining = tickspercycleremaining - 1
        if tickspercycleremaining <= 0 then
            tickspercycleremaining = tickspercycle
            fuelneededpercycle = (fuelneededpercyclecoefficient * heat) + fuelneededpercycleoffset
            
            isburning = fuelburning >= fuelneededpercycle
            if isburning then
                fuelburning = fuelburning - fuelneededpercycle
            end
            
            if heat >= 100 then
                partialconversions = partialconversions + (numberoftanks * heat / maxheat)
                watercost = floor(partialconversions)
                partialconversions = partialconversions - watercost
                steamamount = steamamount + (160 * watercost)
            end
        end
        
        if isburning then
            heat = min(heat + increasingheatchangecoefficient * heat + increasingheatchangeoffset, maxheat)
        else
            heat = heat - decreasingheatchangecoefficient * heat - decreasingheatchangeoffset
        end
    end
    
    return {steamamount = steamamount, maxheatattained = maxheatattained, totalticks = totalticks}
end

local calculatemostefficientboilersize = function(state)
    local completedlowpressurestates = {}
    local completedhighpressurestates = {}
    local index = 1
    local completedstate
    
    for tanksize = 1, 6 do
        completedstate = calculatesteamproduced({tankpressure = 1, tanksize = tanksize, boilertype = state.boilertype, fueltype = state.fueltype, fuelamount = state.fuelamount, startingheat = 20, cooldownheat = 20})
        completedstate.tankpressure = 1
        completedstate.tanksize = tanksize
        
        completedlowpressurestates[index], index = completedstate, index + 1
    end
    tablesort(completedlowpressurestates, sortsteamamounts)
    
    index = 1
    for tanksize = 1, 6 do
        completedstate = calculatesteamproduced({tankpressure = 2, tanksize = tanksize, boilertype = state.boilertype, fueltype = state.fueltype, fuelamount = state.fuelamount, startingheat = 20, cooldownheat = 20})
        completedstate.tankpressure = 2
        completedstate.tanksize = tanksize
        
        completedhighpressurestates[index], index = completedstate, index + 1
    end
    tablesort(completedhighpressurestates, sortsteamamounts)
    
    return {[1] = completedlowpressurestates, [2] = completedhighpressurestates}
end

local calculatefuelconsumptionrate = function(state)
    state.startingheat = state.startingheat or 20
    state.cooldownheat = state.cooldownheat or 20
    state.fuelamount = state.fuelamount or 1000
    
    teststateparameters(state)
    
    local tankpressure = state.tankpressure
    local tanksize = state.tanksize
    local boilertype = state.boilertype
    local fueltype = state.fueltype
    
    local heatvalue = heatvalues[boilertype][fueltypes[boilertype][fueltype]]
    local numberoftanks = tanksizes[tanksize]
    local maxheat = tankpressure == 1 and 500 or 1000
    local fuelneededpercyclemaximum = getfuelneededpercyclemaximum(maxheat, numberoftanks)
    local tickspercycle = tankpressure == 1 and 16 or 8 -- 8 * 1000 / maxheat
    
    return fuelneededpercyclemaximum / (tickspercycle * heatvalue)
end



local getoperationselection = function()
    local runloop = true
    local selection = 1
    local previousselection
    local topofsettingsy
    local event, key, x, y
    
    while runloop do
        if selection ~= previousselection then
            previousselection = selection
            
            clear()
            writetitle()
            writewithcolorflip(false, coloryellow, "What you would like to calculate:\n\n")
            
            _, topofsettingsy = getcursorposition()
            
            writewithcolorflip(selection == 1, colorlime, "1) total steam produced\n")
            writewithcolorflip(selection == 2, colorlime, "2) most efficient boiler\n")
            writewithcolorflip(selection == 3, colorlime, "3) fuel consumption rate\n")
            
            writewithcolorflip(selection == 4, colorred, "\nQuit")
        end
        
        event, key, x, y = pullevent()
        if event == 'key' then
            if key == keyup then
                if selection > 1 then
                    selection = selection - 1
                end
            elseif key == keydown then
                if selection < 4 then
                    selection = selection + 1
                end
            elseif key == keyenter or key == keynumpadenter then
                runloop = false
            end
        elseif event == 'mouse_scroll' then
            if key == scrollup then
                if selection > 1 then
                    selection = selection - 1
                end
            elseif key == scrolldown then
                if selection < 4 then
                    selection = selection + 1
                end
            end
        elseif event == 'char' then
            local num = tonumber(key)
            if num then
                if num >= 1 and num <= 3 then
                    selection = num
                    runloop = false
                end
            elseif key == 'q' then
                selection = 4
                runloop = false
            end
        elseif event == 'mouse_click' or event == 'monitor_touch' then
            local relativeyposition = y - topofsettingsy + 1
            if relativeyposition == 1 and x <= 23 then
                selection = 1
                runloop = false
            elseif relativeyposition == 2 and x <= 24 then
                selection = 2
                runloop = false
            elseif relativeyposition == 3 and x <= 24 then
                selection = 3
                runloop = false
            elseif relativeyposition == 5 and x <= 4 then
                selection = 4
                runloop = false
            end
        end
    end
    return selection
end


local steamproducedoptions = function(state)
    local state = state or {tankpressure = 1, tanksize = 1, boilertype = 1, fueltype = 1, fuelamount = 1000, startingheat = 20, cooldownheat = 20}
    
    local tankpressure = state.tankpressure
    local tanksize = state.tanksize
    local boilertype = state.boilertype
    local fueltype = state.fueltype
    local fuelamount = state.fuelamount -- to be bigint
    local startingheat = state.startingheat
    local cooldownheat = state.cooldownheat
    
    local previoustankpressure = 0
    local previoustanksize = 0
    local previousboilertype = 0
    local previousfueltype = 0
    local maxheat
    local maxfueltype
    local fueltypestring
    local fuelamountstring
    local fuelamountcursorx
    local startingheatcursorx
    local cooldownheatcursorx
    
    local runloop = true
    local selection = 1
    local previousselection
    local topofsettingsy
    local event, key, x, y
    local setdefaults = false
    
    while runloop do
        if selection ~= previousselection or tankpressure ~= previoustankpressure or tanksize ~= previoustanksize or boilertype ~= previousboilertype or fueltype ~= previousfueltype or setdefaults then
            if setdefaults then
                tankpressure = 1
                tanksize = 1
                boilertype = 1
                fueltype = 1
                fuelamount = 1000 -- to be bigint
                startingheat = 20
                cooldownheat = 20
                
                setdefaults = false
            end
            
            previousselection = selection
            previoustankpressure = tankpressure
            previoustanksize = tanksize
            previousboilertype = boilertype
            previousfueltype = fueltype
            maxfueltype = #(fueltypes[boilertype])
            maxheat = tankpressure == 1 and 500 or 1000
            startingheat = constrain(startingheat, 20, maxheat)
            cooldownheat = constrain(cooldownheat, 20, maxheat)
            fuelamount = constrain(fuelamount, 1, maxint)
            fueltypestring = fueltypes[boilertype][fueltype]
            fuelamountstring = formatfuelamount(fuelamount)
            
            clear()
            writetitle()
            writewithcolorflip(false, colorlime, "Total Steam Produced\n\n")
            
            _, topofsettingsy = getcursorposition()
            
            writewithcolorflip(selection == 1, colormagenta, "tank pressure")
            writewithcolorflip(false, colormagenta, ": ")
            writewithcolorflip(tankpressure == 1, colorlightblue, "low")
            writewithcolorflip(false, colorlightblue, " ")
            writewithcolorflip(tankpressure == 2, colorlightblue, "high\n")
            
            writewithcolorflip(selection == 2, colormagenta, "tank size")
            writewithcolorflip(false, colormagenta, ":")
            for i = 1, #tanksizes do
                writewithcolorflip(false, colorlightblue, " ")
                writewithcolorflip(i == tanksize, colorlightblue, tostring(tanksizes[i]))
            end
            
            writewithcolorflip(selection == 3, colormagenta, "\nboiler type")
            writewithcolorflip(false, colormagenta, ": ")
            writewithcolorflip(boilertype == 1, colorlightblue, "liquid")
            writewithcolorflip(false, colorlightblue, " ")
            writewithcolorflip(boilertype == 2, colorlightblue, "solid\n")
            
            writewithcolorflip(selection == 4, colormagenta, "fuel type")
            writewithcolorflip(false, colormagenta, ": ")
            writewithcolorflip(false, colorlightblue, fueltype == 1 and "  -" or "<<-")
            write(fueltype == maxfueltype and "\n  " or ">>\n  ")
            write(fueltypestring)
            write("\n")
            
            writewithcolorflip(selection == 5, colormagenta, "fuel amount")
            writewithcolorflip(false, colormagenta, ": ")
            writewithcolorflip(false, colorlightblue, boilertype == 1 and "mB" or "items")
            write("\n  ")
            fuelamountcursorx, _ = getcursorposition()
            write(fuelamountstring)
            
            writewithcolorflip(selection == 6, colormagenta, "\nstarting heat")
            writewithcolorflip(false, colormagenta, ": ")
            startingheatcursorx, _ = getcursorposition()
            writewithcolorflip(false, colorlightblue, tostring(startingheat))
            
            writewithcolorflip(selection == 7, colormagenta, "\ncool-down heat")
            writewithcolorflip(false, colormagenta, ": ")
            cooldownheatcursorx, _ = getcursorposition()
            writewithcolorflip(false, colorlightblue, tostring(cooldownheat))
            
            writewithcolorflip(selection == 8, colorlime, "\n\nCalculate\n")
            writewithcolorflip(selection == 9, colorpink, "Default\n")
            writewithcolorflip(selection == 10, coloryellow, "Previous\n")
            writewithcolorflip(selection == 11, colorred, "Quit")
            
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
                settextcolor(colorlightblue)
                setcursorblink(true)
            end
        end
        
        event, key, x, y = pullevent()
        if event == 'key' then
            if key == keyup then
                if selection > 1 then
                    selection = selection - 1
                end
            elseif key == keydown then
                if selection < 11 then
                    selection = selection + 1
                end
            elseif key == keyright then
                if selection == 1 then
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
                if selection == 1 then
                    tankpressure = 1
                elseif selection == 2 and tanksize > 1 then
                    tanksize = tanksize - 1
                elseif selection == 3 and boilertype == 2 then
                    boilertype = 1
                    fueltype = 1
                elseif selection == 4 and fueltype > 1 then
                    fueltype = fueltype - 1
                end
            elseif key == keyenter or key == keynumpadenter then
                if selection == 9 then
                    setdefaults = true
                elseif selection >= 8 then
                    runloop = false
                else
                    selection = 8
                end
            elseif key == keybackspace then
                if selection == 5 then
                    fuelamount = floor(fuelamount / 10)
                    fuelamountstring = formatfuelamount(fuelamount)
                    setcursorposition(fuelamountcursorx, topofsettingsy + 6)
                    writewithcolorflip(false, colorlightblue, fuelamountstring)
                    write(" ")
                    shiftcursorposition(-1, 0)
                elseif selection == 6 then
                    startingheat = floor(startingheat / 10)
                    setcursorposition(startingheatcursorx, topofsettingsy + 7)
                    writewithcolorflip(false, colorlightblue, tostring(startingheat))
                    write(" ")
                    shiftcursorposition(-1, 0)
                elseif selection == 7 then
                    cooldownheat = floor(cooldownheat / 10)
                    setcursorposition(cooldownheatcursorx, topofsettingsy + 8)
                    writewithcolorflip(false, colorlightblue, tostring(cooldownheat))
                    write(" ")
                    shiftcursorposition(-1, 0)
                end
            end
        elseif event == 'mouse_scroll' then
            if key == scrollup then
                if selection > 1 then
                    selection = selection - 1
                end
            elseif key == scrolldown then
                if selection < 11 then
                    selection = selection + 1
                end
            end
        elseif event == 'char' then
            local num = tonumber(key)
            if num then
                if selection == 5 then
                    fuelamount = fuelamount * 10 + num
                    fuelamountstring = formatfuelamount(fuelamount)
                    setcursorposition(fuelamountcursorx, topofsettingsy + 6)
                    writewithcolorflip(false, colorlightblue, fuelamountstring)
                elseif selection == 6 then
                    startingheat = startingheat * 10 + num
                    if startingheat < 10 then
                        shiftcursorposition(-1, 0)
                    end
                    writewithcolorflip(false, colorlightblue, key)
                elseif selection == 7 then
                    cooldownheat = cooldownheat * 10 + num
                    if cooldownheat < 10 then
                        shiftcursorposition(-1, 0)
                    end
                    writewithcolorflip(false, colorlightblue, key)
                end
            elseif key == 'p' then
                runloop = false
                selection = 10
            elseif key == 'q' then
                runloop = false
                selection = 11
            end
        elseif event == 'mouse_click' or event == 'monitor_touch' then
            local relativeyposition = y - topofsettingsy + 1
            if relativeyposition == 1 and x <= 23 then
                selection = 1
                if x >= 16 and x <= 18 then
                    tankpressure = 1
                elseif x >= 20 and x <= 23 then
                    tankpressure = 2
                end
            elseif relativeyposition == 2 and x <= 26 then
                selection = 2
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
            elseif relativeyposition == 3 and x <= 25 then
                selection = 3
                if x >= 14 and x <= 19 then
                    boilertype = 1
                    fueltype = 1
                elseif x >= 21 and x <= 25 then
                    boilertype = 2
                    fueltype = 1
                end
            elseif (relativeyposition == 4 and x <= 16) or (relativeyposition == 5 and x <= #fueltypestring + 2) then
                selection = 4
                if (x == 12 or x == 13) and fueltype > 1 then
                    fueltype = fueltype - 1
                elseif (x == 15 or x == 16) and fueltype < maxfueltype then
                    fueltype = fueltype + 1
                end
            elseif (relativeyposition == 6 and x <= 13 + (boilertype == 1 and 2 or 5)) or (relativeyposition == 7 and x <= #fuelamountstring + 3) then
                selection = 5
            elseif relativeyposition == 8 and x <= 16 + #tostring(startingheat) then
                selection = 6
            elseif relativeyposition == 9 and x <= 17 + #tostring(cooldownheat) then
                selection = 7
            elseif relativeyposition == 11 and x <= 9 then
                selection = 8
                runloop = false
            elseif relativeyposition == 12 and x <= 7 then
                selection = 9
                setdefaults = true
            elseif relativeyposition == 13 and x <= 8 then
                selection = 10
                runloop = false
            elseif relativeyposition == 14 and x <= 4 then
                selection = 11
                runloop = false
            end
        end
    end
    
    return selection, {tankpressure = tankpressure, tanksize = tanksize, boilertype = boilertype, fueltype = fueltype, fuelamount = fuelamount, startingheat = startingheat, cooldownheat = cooldownheat}
end

local steamproducedresults = function(state)
    local completedstate = calculatesteamproduced(state)
    
    local steamamount = completedstate.steamamount
    local maxheatattained = completedstate.maxheatattained
    local totalticks = completedstate.totalticks
    
    local hours = floor(totalticks / 72000)
    local minutes = floor(totalticks / 1200) % 60
    local secondsinteger = floor(totalticks / 20) % 60
    local secondsdecimal = totalticks % 20 * 5
    local formattedtimestring = stringformat('%d ticks\n   %dh %dm %d.%02ds\n\n', totalticks, hours, minutes, secondsinteger, secondsdecimal)
    
    local runloop = true
    local selection = 1
    local previousselection
    local topofsettingsy
    local event, key, x, y
    
    while runloop do
        if previousselection ~= selection then
            previousselection = selection
            
            clear()
            writetitle()
            
            writewithcolorflip(false, colorlime, "Boiler Calculation Results\n\n")
            writewithcolorflip(false, coloryellow, "Note: Calculated results and actual results may differ slightly\n\n")
            
            writewithcolorflip(false, colorpink, "Steam: ")
            writewithcolorflip(false, colorlightblue, steamamount)
            write(" mB\n")
            writewithcolorflip(false, colorpink, "Max heat: ")
            writewithcolorflip(false, colorlightblue, maxheatattained)
            write("\n")
            writewithcolorflip(false, colorpink, "Time taken: ")
            writewithcolorflip(false, colorlightblue, formattedtimestring)
            
            _, topofsettingsy = getcursorposition()
            
            writewithcolorflip(selection == 1, coloryellow, "Previous\n")
            writewithcolorflip(selection == 2, colorred, "Quit")
        end
        
        event, key, x, y = pullevent()
        if event == 'key' then
            if key == keyup then
                selection = 1
            elseif key == keydown then
                selection = 2
            elseif key == keyenter or key == keynumpadenter then
                runloop = false
            end
        elseif event == 'mouse_scroll' then
            if key == scrollup then
                selection = 1
            elseif key == scrolldown then
                selection = 2
            end
        elseif event == 'char' then
            if key == 'p' then
                selection = 1
                runloop = false
            elseif key == 'q' then
                selection = 2
                runloop = false
            end
        elseif event == 'mouse_click' or event == 'monitor_touch' then
            if y == topofsettingsy and x <= 8 then
                selection = 1
                runloop = false
            elseif y == topofsettingsy + 1 and x <= 4 then
                selection = 2
                runloop = false
            end
        end
    end
    
    return selection
end


local mostefficientoptions = function(state)
    local state = state or {boilertype = 1, fueltype = 1, fuelamount = 1000}
    
    local boilertype = state.boilertype
    local fueltype = state.fueltype
    local fuelamount = state.fuelamount -- to be bigint
    
    local previousboilertype = 0
    local previousfueltype = 0
    local maxfueltype
    local fueltypestring
    local fuelamountstring
    local fuelamountcursorx
    
    local runloop = true
    local selection = 1
    local previousselection
    local topofsettingsy
    local event, key, x, y
    local setdefaults = false
    
    while runloop do
        if selection ~= previousselection or boilertype ~= previousboilertype or fueltype ~= previousfueltype or setdefaults then
            if setdefaults then
                boilertype = 1
                fueltype = 1
                fuelamount = 1000 -- to be bigint
                
                setdefaults = false
            end
            
            previousselection = selection
            previousboilertype = boilertype
            previousfueltype = fueltype
            maxfueltype = #(fueltypes[boilertype])
            fuelamount = constrain(fuelamount, 1, maxint)
            fueltypestring = fueltypes[boilertype][fueltype]
            fuelamountstring = formatfuelamount(fuelamount)
            
            clear()
            writetitle()
            writewithcolorflip(false, colorlime, "Most Efficient Boiler Size\n\n")
            
            _, topofsettingsy = getcursorposition()
            
            writewithcolorflip(selection == 1, colormagenta, "boiler type")
            writewithcolorflip(false, colormagenta, ": ")
            writewithcolorflip(boilertype == 1, colorlightblue, "liquid")
            writewithcolorflip(false, colorlightblue, " ")
            writewithcolorflip(boilertype == 2, colorlightblue, "solid\n")
            
            writewithcolorflip(selection == 2, colormagenta, "fuel type")
            writewithcolorflip(false, colormagenta, ": ")
            writewithcolorflip(false, colorlightblue, fueltype == 1 and "  -" or "<<-")
            write(fueltype == maxfueltype and "\n  " or ">>\n  ")
            write(fueltypestring)
            write("\n")
            
            writewithcolorflip(selection == 3, colormagenta, "fuel amount")
            writewithcolorflip(false, colormagenta, ": ")
            writewithcolorflip(false, colorlightblue, boilertype == 1 and "mB" or "items")
            write("\n  ")
            fuelamountcursorx, _ = getcursorposition()
            write(fuelamountstring)
            
            writewithcolorflip(selection == 4, colorlime, "\n\nCalculate\n")
            writewithcolorflip(selection == 5, colorpink, "Default\n")
            writewithcolorflip(selection == 6, coloryellow, "Previous\n")
            writewithcolorflip(selection == 7, colorred, "Quit")
            
            if selection == 3 then
                setcursorposition(fuelamountcursorx + #fuelamountstring, topofsettingsy + 4)
                settextcolor(colorlightblue)
                setcursorblink(true)
            else
                setcursorblink(false)
            end
        end
        
        event, key, x, y = pullevent()
        if event == 'key' then
            if key == keyup then
                if selection > 1 then
                    selection = selection - 1
                end
            elseif key == keydown then
                if selection < 7 then
                    selection = selection + 1
                end
            elseif key == keyright then
                if selection == 1 then
                    boilertype = 2
                elseif selection == 2 and fueltype < maxfueltype then
                    fueltype = fueltype + 1
                end
            elseif key == keyleft then
                if selection == 1 then
                    boilertype = 1
                elseif selection == 2 and fueltype > 1 then
                    fueltype = fueltype - 1
                end
            elseif key == keyenter or key == keynumpadenter then
                if selection == 5 then
                    setdefaults = true
                elseif selection >= 4 then
                    runloop = false
                else
                    selection = 4
                end
            elseif key == keybackspace then
                if selection == 3 then
                    fuelamount = floor(fuelamount / 10)
                    fuelamountstring = formatfuelamount(fuelamount)
                    setcursorposition(fuelamountcursorx, topofsettingsy + 4)
                    writewithcolorflip(false, colorlightblue, fuelamountstring)
                    write(" ")
                    shiftcursorposition(-1, 0)
                end
            end
        elseif event == 'mouse_scroll' then
            if key == scrollup then
                if selection > 1 then
                    selection = selection - 1
                end
            elseif key == scrolldown then
                if selection < 7 then
                    selection = selection + 1
                end
            end
        elseif event == 'char' then
            local num = tonumber(key)
            if num then
                if selection == 3 then
                    fuelamount = fuelamount * 10 + num
                    fuelamountstring = formatfuelamount(fuelamount)
                    setcursorposition(fuelamountcursorx, topofsettingsy + 4)
                    writewithcolorflip(false, colorlightblue, fuelamountstring)
                end
            elseif key == 'p' then
                runloop = false
                selection = 6
            elseif key == 'q' then
                runloop = false
                selection = 7
            end
        elseif event == 'mouse_click' or event == 'monitor_touch' then
            local relativeyposition = y - topofsettingsy + 1
            if relativeyposition == 1 and x <= 25 then
                selection = 1
                if x >= 14 and x <= 19 then
                    boilertype = 1
                    fueltype = 1
                elseif x >= 21 and x <= 25 then
                    boilertype = 2
                    fueltype = 1
                end
            elseif (relativeyposition == 2 and x <= 16) or (relativeyposition == 3 and x <= #fueltypestring + 2) then
                selection = 2
                if (x == 12 or x == 13) and fueltype > 1 then
                    fueltype = fueltype - 1
                elseif (x == 15 or x == 16) and fueltype < maxfueltype then
                    fueltype = fueltype + 1
                end
            elseif (relativeyposition == 4 and x <= 13 + (boilertype == 1 and 2 or 6)) or (relativeyposition == 5 and x <= #fuelamountstring + 3) then
                selection = 3
            elseif relativeyposition == 7 and x <= 9 then
                selection = 4
                runloop = false
            elseif relativeyposition == 8 and x <= 7 then
                selection = 5
                setdefaults = true
            elseif relativeyposition == 9 and x <= 8 then
                selection = 6
                runloop = false
            elseif relativeyposition == 10 and x <= 4 then
                selection = 7
                runloop = false
            end
        end
    end
    
    return selection, {boilertype = boilertype, fueltype = fueltype, fuelamount = fuelamount}
end

local mostefficientresults = function(state)
    local mostefficientboilers = calculatemostefficientboilersize(state)
    
    local mostefficientlowpressureboiler = mostefficientboilers[1][1]
    local lowpressuresteamamount = mostefficientlowpressureboiler.steamamount
    local lowpressuretankpressure = mostefficientlowpressureboiler.tankpressure
    local lowpressuretanksize = mostefficientlowpressureboiler.tanksize
    
    local mostefficienthighpressureboiler = mostefficientboilers[2][1]
    local highpressuresteamamount = mostefficienthighpressureboiler.steamamount
    local highpressuretankpressure = mostefficienthighpressureboiler.tankpressure
    local highpressuretanksize = mostefficienthighpressureboiler.tanksize
    
    local runloop = true
    local selection = 1
    local previousselection
    local topofsettingsy
    local event, key, x, y
    
    while runloop do
        if previousselection ~= selection then
            previousselection = selection
            
            clear()
            writetitle()
            
            writewithcolorflip(false, colorlime, "Boiler Efficiency Results\n\n")
            writewithcolorflip(false, coloryellow, "Note: Calculated results and actual results may differ slightly\n\n")
            
            writewithcolorflip(false, colorpink, "Tank pressure: ")
            writewithcolorflip(false, colorlightblue, "low\n")
            writewithcolorflip(false, colorpink, "Tank size: ")
            writewithcolorflip(false, colorlightblue, tanksizes[lowpressuretanksize])
            writewithcolorflip(false, colorpink, "\nSteam: ")
            writewithcolorflip(false, colorlightblue, lowpressuresteamamount)
            write(" mB\n\n")
            
            writewithcolorflip(false, colorpink, "Tank pressure: ")
            writewithcolorflip(false, colorlightblue, "high\n")
            writewithcolorflip(false, colorpink, "Tank size: ")
            writewithcolorflip(false, colorlightblue, tanksizes[highpressuretanksize])
            writewithcolorflip(false, colorpink, "\nSteam: ")
            writewithcolorflip(false, colorlightblue, highpressuresteamamount)
            write(" mB\n\n")
            
            _, topofsettingsy = getcursorposition()
            
            writewithcolorflip(selection == 1, coloryellow, "Previous\n")
            writewithcolorflip(selection == 2, colorred, "Quit")
        end
        
        event, key, x, y = pullevent()
        if event == 'key' then
            if key == keyup then
                selection = 1
            elseif key == keydown then
                selection = 2
            elseif key == keyenter or key == keynumpadenter then
                runloop = false
            end
        elseif event == 'mouse_scroll' then
            if key == scrollup then
                selection = 1
            elseif key == scrolldown then
                selection = 2
            end
        elseif event == 'char' then
            if key == 'p' then
                selection = 1
                runloop = false
            elseif key == 'q' then
                selection = 2
                runloop = false
            end
        elseif event == 'mouse_click' or event == 'monitor_touch' then
            if y == topofsettingsy and x <= 8 then
                selection = 1
                runloop = false
            elseif y == topofsettingsy + 1 and x <= 4 then
                selection = 2
                runloop = false
            end
        end
    end
    
    return selection
end


local fuelconsumptionrateoptions = function(state)
    local state = state or {tankpressure = 1, tanksize = 1, boilertype = 1, fueltype = 1, fuelamount = 1000, startingheat = 20, cooldownheat = 20}
    
    local tankpressure = state.tankpressure
    local tanksize = state.tanksize
    local boilertype = state.boilertype
    local fueltype = state.fueltype
    
    local previoustankpressure = 0
    local previoustanksize = 0
    local previousboilertype = 0
    local previousfueltype = 0
    local maxfueltype
    local fueltypestring
    local fuelamountstring
    
    local runloop = true
    local selection = 1
    local previousselection
    local topofsettingsy
    local event, key, x, y
    local setdefaults = false
    
    while runloop do
        if selection ~= previousselection or tankpressure ~= previoustankpressure or tanksize ~= previoustanksize or boilertype ~= previousboilertype or fueltype ~= previousfueltype or setdefaults then
            if setdefaults then
                tankpressure = 1
                tanksize = 1
                boilertype = 1
                fueltype = 1
                
                setdefaults = false
            end
            
            previousselection = selection
            previoustankpressure = tankpressure
            previoustanksize = tanksize
            previousboilertype = boilertype
            previousfueltype = fueltype
            maxfueltype = #(fueltypes[boilertype])
            fueltypestring = fueltypes[boilertype][fueltype]
            
            clear()
            writetitle()
            writewithcolorflip(false, colorlime, "Fuel Consumption Rate\n\n")
            
            _, topofsettingsy = getcursorposition()
            
            writewithcolorflip(selection == 1, colormagenta, "tank pressure")
            writewithcolorflip(false, colormagenta, ": ")
            writewithcolorflip(tankpressure == 1, colorlightblue, "low")
            writewithcolorflip(false, colorlightblue, " ")
            writewithcolorflip(tankpressure == 2, colorlightblue, "high\n")
            
            writewithcolorflip(selection == 2, colormagenta, "tank size")
            writewithcolorflip(false, colormagenta, ":")
            for i = 1, #tanksizes do
                writewithcolorflip(false, colorlightblue, " ")
                writewithcolorflip(i == tanksize, colorlightblue, tostring(tanksizes[i]))
            end
            
            writewithcolorflip(selection == 3, colormagenta, "\nboiler type")
            writewithcolorflip(false, colormagenta, ": ")
            writewithcolorflip(boilertype == 1, colorlightblue, "liquid")
            writewithcolorflip(false, colorlightblue, " ")
            writewithcolorflip(boilertype == 2, colorlightblue, "solid\n")
            
            writewithcolorflip(selection == 4, colormagenta, "fuel type")
            writewithcolorflip(false, colormagenta, ": ")
            writewithcolorflip(false, colorlightblue, fueltype == 1 and "  -" or "<<-")
            write(fueltype == maxfueltype and "\n  " or ">>\n  ")
            write(fueltypestring)
            
            writewithcolorflip(selection == 5, colorlime, "\n\nCalculate\n")
            writewithcolorflip(selection == 6, colorpink, "Default\n")
            writewithcolorflip(selection == 7, coloryellow, "Previous\n")
            writewithcolorflip(selection == 8, colorred, "Quit")
        end
        
        event, key, x, y = pullevent()
        if event == 'key' then
            if key == keyup then
                if selection > 1 then
                    selection = selection - 1
                end
            elseif key == keydown then
                if selection < 8 then
                    selection = selection + 1
                end
            elseif key == keyright then
                if selection == 1 then
                    tankpressure = 2
                elseif selection == 2 and tanksize < 6 then
                    tanksize = tanksize + 1
                elseif selection == 3 and boilertype == 1 then
                    boilertype = 2
                    fueltype = 1
                elseif selection == 4 and fueltype < maxfueltype then
                    fueltype = fueltype + 1
                end
            elseif key == keyleft then
                if selection == 1 then
                    tankpressure = 1
                elseif selection == 2 and tanksize > 1 then
                    tanksize = tanksize - 1
                elseif selection == 3 and boilertype == 2 then
                    boilertype = 1
                    fueltype = 1
                elseif selection == 4 and fueltype > 1 then
                    fueltype = fueltype - 1
                end
            elseif key == keyenter or key == keynumpadenter then
                if selection == 6 then
                    setdefaults = true
                elseif selection >= 5 then
                    runloop = false
                else
                    selection = 5
                end
            end
        elseif event == 'mouse_scroll' then
            if key == scrollup then
                if selection > 1 then
                    selection = selection - 1
                end
            elseif key == scrolldown then
                if selection < 8 then
                    selection = selection + 1
                end
            end
        elseif event == 'char' then
            if key == 'p' then
                runloop = false
                selection = 7
            elseif key == 'q' then
                runloop = false
                selection = 8
            end
        elseif event == 'mouse_click' or event == 'monitor_touch' then
            local relativeyposition = y - topofsettingsy + 1
            if relativeyposition == 1 and x <= 23 then
                selection = 1
                if x >= 16 and x <= 18 then
                    tankpressure = 1
                elseif x >= 20 and x <= 23 then
                    tankpressure = 2
                end
            elseif relativeyposition == 2 and x <= 26 then
                selection = 2
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
            elseif relativeyposition == 3 and x <= 25 then
                selection = 3
                if x >= 14 and x <= 19 then
                    boilertype = 1
                    fueltype = 1
                elseif x >= 21 and x <= 25 then
                    boilertype = 2
                    fueltype = 1
                end
            elseif (relativeyposition == 4 and x <= 16) or (relativeyposition == 5 and x <= #fueltypestring + 2) then
                selection = 4
                if (x == 12 or x == 13) and fueltype > 1 then
                    fueltype = fueltype - 1
                elseif (x == 15 or x == 16) and fueltype < maxfueltype then
                    fueltype = fueltype + 1
                end
            elseif relativeyposition == 7 and x <= 9 then
                selection = 5
                runloop = false
            elseif relativeyposition == 8 and x <= 7 then
                selection = 6
                setdefaults = true
            elseif relativeyposition == 9 and x <= 8 then
                selection = 7
                runloop = false
            elseif relativeyposition == 10 and x <= 4 then
                selection = 8
                runloop = false
            end
        end
    end
    
    return selection, {tankpressure = tankpressure, tanksize = tanksize, boilertype = boilertype, fueltype = fueltype}
end

local fuelconsumptionrateresults = function(state)
    local boilertype = state.boilertype
    local fuelconsumptionrate = calculatefuelconsumptionrate(state)
    
    --[[local formatfuelconsumptionrate = function(fuelconsumptionrate, suffix)
        local screensizex = getscreensize()
        local allowednumberwidth = screensizex - 6 - #suffix
        local fcrinteger = floor(fuelconsumptionrate)
        local remainingdecimalnumberwidth--]]
    
    local formattedfuelratestring
    if boilertype == 1 then
        formattedfuelratestring = stringformat("%f mB/tick\n\n", fuelconsumptionrate * 1000)
    else
        formattedfuelratestring = stringformat("%f items/tick\n\n", fuelconsumptionrate)
    end
    
    local runloop = true
    local selection = 1
    local previousselection
    local topofsettingsy
    local event, key, x, y
    
    while runloop do
        if previousselection ~= selection then
            previousselection = selection
            
            clear()
            writetitle()
            
            writewithcolorflip(false, colorlime, "Fuel Consumption Results\n\n")
            writewithcolorflip(false, coloryellow, "Note: Calculated results and actual results may differ slightly\n\n")
            
            writewithcolorflip(false, colorpink, "Rate: ")
            writewithcolorflip(false, colorlightblue, formattedfuelratestring)
            
            _, topofsettingsy = getcursorposition()
            
            writewithcolorflip(selection == 1, coloryellow, "Previous\n")
            writewithcolorflip(selection == 2, colorred, "Quit")
        end
        
        event, key, x, y = pullevent()
        if event == 'key' then
            if key == keyup then
                selection = 1
            elseif key == keydown then
                selection = 2
            elseif key == keyenter or key == keynumpadenter then
                runloop = false
            end
        elseif event == 'mouse_scroll' then
            if key == scrollup then
                selection = 1
            elseif key == scrolldown then
                selection = 2
            end
        elseif event == 'char' then
            if key == 'p' then
                selection = 1
                runloop = false
            elseif key == 'q' then
                selection = 2
                runloop = false
            end
        elseif event == 'mouse_click' or event == 'monitor_touch' then
            if y == topofsettingsy and x <= 8 then
                selection = 1
                runloop = false
            elseif y == topofsettingsy + 1 and x <= 4 then
                selection = 2
                runloop = false
            end
        end
    end
    
    return selection
end



local processcontroller = function()
    local run = true
    local process = 0
    local selection, state
    
    while run do
        if process == 0 then
            selection = getoperationselection()
            state = nil
            
            if selection == 4 then
                process = -1
            else
                process = selection * 10
            end
        elseif process == 10 then
            selection, state = steamproducedoptions(state)
            
            if selection == 8 then
                process = 11
            elseif selection == 10 then
                process = 0
            elseif selection == 11 then
                process = -1
            else
                process = -2
            end
        elseif process == 11 then
            selection = steamproducedresults(state)
            
            if selection == 1 then
                process = 10
            elseif selection == 2 then
                process = -1
            else
                process = -2
            end
        elseif process == 20 then
            selection, state = mostefficientoptions(state)
            
            if selection == 4 then
                process = 21
            elseif selection == 6 then
                process = 0
            elseif selection == 7 then
                process = -1
            else
                process = -2
            end
        elseif process == 21 then
            selection = mostefficientresults(state)
            
            if selection == 1 then
                process = 20
            elseif selection == 2 then
                process = -1
            else
                process = -2
            end
        elseif process == 30 then
            selection, state = fuelconsumptionrateoptions(state)
            
            if selection == 5 then
                process = 31
            elseif selection == 7 then
                process = 0
            elseif selection == 8 then
                process = -1
            else
                process = -2
            end
        elseif process == 31 then
            selection = fuelconsumptionrateresults(state)
            
            if selection == 1 then
                process = 30
            elseif selection == 2 then
                process = -1
            else
                process = -2
            end
        elseif process == -1 then
            clear()
            run = false
        elseif process == -2 then
            clear()
            writewithcolorflip(false, colorred, "Unusual unhandled exception occurred. Sorry.\n")
            run = false
        else
            process = -2
        end
    end
end

processcontroller()
