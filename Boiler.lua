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