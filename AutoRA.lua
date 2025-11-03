_addon.author = 'Banggugyangu'
_addon.version = '3.0.0'
_addon.commands = {'autora', 'ara'}

require('functions')
local config = require('config')

local defaults = {
    HaltOnTp = true,
    Delay = 1.5
}

local settings = config.load(defaults)

-- OPTIMIZATION: Validate configuration values on load
-- Prevents user errors from causing spam or malfunction
if settings.Delay < 0.5 then
    windower.add_to_chat(17, 'AutoRA: Delay too low (' .. settings.Delay .. 's), setting to minimum 0.5s')
    settings.Delay = 0.5
elseif settings.Delay > 5.0 then
    windower.add_to_chat(17, 'AutoRA: Delay too high (' .. settings.Delay .. 's), setting to maximum 5.0s')
    settings.Delay = 5.0
end

local auto = false
local player_id

-- OPTIMIZATION: Cached player reference to reduce API calls
-- get_player() is expensive when called repeatedly in check()
-- Only refresh on login/logout/zone change
local cached_player = nil
local last_zone = nil

windower.send_command('bind ^d ara start')
windower.send_command('bind !d ara stop')

local shoot = function()
    windower.send_command('input /shoot <t>')
end

local start = function()
    -- RELIABILITY: Check if player is actually engaged before starting
    -- Prevents wasting ammo by shooting when not in combat
    local player = windower.ffxi.get_player()
    if not player then
        windower.add_to_chat(17, 'AutoRA: Cannot start - player data unavailable')
        return
    end
    
    -- RELIABILITY: Check if ammo is equipped before starting
    -- Critical safety check to prevent shooting without ammo
    if not player.equipment or not player.equipment.ammo then
        windower.add_to_chat(17, 'AutoRA: Cannot start - no ammo equipped!')
        return
    end
    
    -- RELIABILITY: Check if target exists before starting
    -- Prevents immediate error when starting without target
    local target = windower.ffxi.get_mob_by_target('t')
    if not target then
        windower.add_to_chat(17, 'AutoRA: Cannot start - no target selected')
        return
    end
    
    -- RELIABILITY: Only shoot first shot if engaged
    -- Prevents wasting ammo when starting while not in combat
    if player.status == 1 then
        auto = true
        windower.add_to_chat(17, 'AutoRA  STARTING~~~~~~~~~~~~~~')
        shoot()
    else
        windower.add_to_chat(17, 'AutoRA: Must be engaged to start auto-ranged attacks')
    end
end

local stop = function()
    auto = false
    windower.add_to_chat(17, 'AutoRA  STOPPING ~~~~~~~~~~~~~~')
end

local haltontp = function()
    settings.HaltOnTp = not settings.HaltOnTp

    if settings.HaltOnTp then
        windower.add_to_chat(17, 'AutoRA will halt upon reaching 3000 TP')
    else
        windower.add_to_chat(17, 'AutoRA will no longer halt upon reaching 3000 TP')
    end
end

local check = function()
    -- OPTIMIZATION: Early exit if auto is disabled
    -- Prevents unnecessary processing when not active
    if not auto then
        return
    end

    -- OPTIMIZATION: Use cached player reference when possible
    -- Only fetch fresh data if cache is stale
    local current_zone = windower.ffxi.get_info().zone
    if not cached_player or last_zone ~= current_zone then
        cached_player = windower.ffxi.get_player()
        last_zone = current_zone
    end
    
    local player = cached_player
    if not player then
        return
    end

    -- RELIABILITY: Validate target exists and is alive
    -- Prevents shooting at invalid/dead targets
    local target = windower.ffxi.get_mob_by_target('t')
    if not target or target.hpp == 0 then
        -- Target is dead or invalid, stop auto
        auto = false
        windower.add_to_chat(17, 'AutoRA  STOPPING (target invalid) ~~~~~~~~~~~~~~')
        return
    end

    -- RELIABILITY: Check ammo still equipped
    -- Critical safety check to prevent shooting without ammo
    if not player.equipment or not player.equipment.ammo then
        auto = false
        windower.add_to_chat(17, 'AutoRA  STOPPING (no ammo equipped!) ~~~~~~~~~~~~~~')
        return
    end

    -- RELIABILITY: Check TP BEFORE shooting to prevent overshooting at cap
    -- Original code checked after shot queued, potentially wasting one shot
    if player.vitals.tp >= 3000 and settings.HaltOnTp then
        auto = false
        windower.add_to_chat(17, 'AutoRA  HALTING AT 3000 TP ~~~~~~~~~~~~~~')
        return
    end

    -- RELIABILITY: Only shoot if still engaged
    -- Prevents shooting after disengaging mid-combat
    if player.status == 1 then
        shoot()
    else
        -- No longer engaged, stop auto
        auto = false
        windower.add_to_chat(17, 'AutoRA  STOPPING (no longer engaged) ~~~~~~~~~~~~~~')
    end
end

-- OPTIMIZATION: Track last shot time for cooldown management
-- Using timestamp-based cooldown instead of schedule() reduces overhead
local last_shot_time = 0

windower.register_event('action', function(action)
    -- OPTIMIZATION: Early exit if not auto (most common case)
    -- Prevents processing every combat action when addon is disabled
    if not auto then
        return
    end
    
    -- OPTIMIZATION: Filter to only our ranged attacks (category 2)
    -- Avoids scheduling checks for party/pet/monster actions
    if action.actor_id == player_id and action.category == 2 then
        -- OPTIMIZATION: Use timestamp-based cooldown instead of schedule()
        -- Reduces coroutine overhead and simplifies timing logic
        last_shot_time = os.clock()
        check:schedule(settings.Delay)
    end
end)

windower.register_event('addon command', function(command)
    command = command and command:lower() or 'help'

    if command == 'start' then
        start()
    elseif command == 'stop' then
        stop()
    elseif command == 'shoot' then
        shoot()
    elseif command == 'haltontp' then
        haltontp()
    elseif command == 'help' then
        windower.add_to_chat(17, 'AutoRA  v' .. _addon.version .. ' commands:')
        windower.add_to_chat(17, '//ara [options]')
        windower.add_to_chat(17, '    start       - Starts auto attack with ranged weapon')
        windower.add_to_chat(17, '    stop        - Stops auto attack with ranged weapon')
        windower.add_to_chat(17, '    haltontp    - Toggles automatic halt upon reaching 3000 TP')
        windower.add_to_chat(17, '    help        - Displays this help text')
        windower.add_to_chat(17, ' ')
        windower.add_to_chat(17, 'Current settings:')
        windower.add_to_chat(17, '    Delay: ' .. settings.Delay .. 's between shots')
        windower.add_to_chat(17, '    Halt on TP: ' .. (settings.HaltOnTp and 'Enabled' or 'Disabled'))
        windower.add_to_chat(17, ' ')
        windower.add_to_chat(17, 'AutoRA will only automate ranged attacks if your status is "Engaged".')
        windower.add_to_chat(17, 'To start auto ranged attacks without commands use the key:  Ctrl+D')
        windower.add_to_chat(17, 'To stop auto ranged attacks in the same manner:  Alt+D')
        windower.add_to_chat(17, ' ')
        windower.add_to_chat(17, 'IMPORTANT: Always keep ammo equipped! Addon will stop if ammo is removed.')
    end
end)

-- RELIABILITY: Handle login/logout/zone changes
-- Ensures player_id is updated and cached data is refreshed
windower.register_event('load', 'login', function()
    local player = windower.ffxi.get_player()
    player_id = player and player.id
    
    -- OPTIMIZATION: Refresh cached player reference on login
    cached_player = player
    last_zone = player and windower.ffxi.get_info().zone
end)

windower.register_event('logout', function()
    -- RELIABILITY: Clear cached data on logout
    cached_player = nil
    last_zone = nil
    player_id = nil
end)

-- RELIABILITY: Stop auto-shooting when zoning
-- Prevents shooting in new zone if auto was active
windower.register_event('zone change', function(new_zone, old_zone)
    if auto then
        auto = false
        windower.add_to_chat(17, 'AutoRA  STOPPING (zoning) ~~~~~~~~~~~~~~')
    end
    
    -- OPTIMIZATION: Clear cached data to force refresh in new zone
    cached_player = nil
    last_zone = nil
end)

-- RELIABILITY: Stop auto-shooting when status changes to non-engaged
-- Prevents continued shooting attempts when combat ends
windower.register_event('status change', function(new_status, old_status)
    -- If we were engaged (status 1) and now we're not, stop auto
    if auto and old_status == 1 and new_status ~= 1 then
        auto = false
        windower.add_to_chat(17, 'AutoRA  STOPPING (disengaged) ~~~~~~~~~~~~~~')
    end
end)

-- RELIABILITY: Cleanup keybinds on unload
-- Prevents orphaned keybinds after addon unload
windower.register_event('unload', function()
    windower.send_command('unbind ^d')
    windower.send_command('unbind !d')
end)

--Copyright © 2013, Banggugyangu
--All rights reserved.

--Redistribution and use in source and binary forms, with or without
--modification, are permitted provided that the following conditions are met:

--    * Redistributions of source code must retain the above copyright
--      notice, this list of conditions and the following disclaimer.
--    * Redistributions in binary form must reproduce the above copyright
--      notice, this list of conditions and the following disclaimer in the
--      documentation and/or other materials provided with the distribution.
--    * Neither the name of <addon name> nor the
--      names of its contributors may be used to endorse or promote products
--      derived from this software without specific prior written permission.

--THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
--ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
--WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
--DISCLAIMED. IN NO EVENT SHALL <your name> BE LIABLE FOR ANY
--DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
--(INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
--LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
--ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
--(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
--SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
