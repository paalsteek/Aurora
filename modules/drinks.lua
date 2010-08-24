-- -------------------------------------------------------------------------- --
-- Aurora - drinks.lua - Module to store the consumption of coffein.          --
-- -------------------------------------------------------------------------- --
-- Copyright (C) 2010 Stephan Platz <aurora@stephan-platz.de>                 --
--                                                                            --
-- This program is free software; you can redistribute it and/or modify it    --
-- under the terms of the GNU General Public License as published by the      --
-- Free Software Foundation; either version 3 of the License,                 --
-- or (at your option) any later version.                                     --
--                                                                            --
-- This program is distributed in the hope that it will be useful, but        --
-- WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY --
-- or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License    --
-- for more details.                                                          --
--                                                                            --
-- You should have received a copy of the GNU General Public License along    --
-- with this program; if not, see <http://www.gnu.org/licenses/>.             --
-- -------------------------------------------------------------------------- --

require "luasql.sqlite3"
--require "logging.console"
local pcre = require("rex_pcre")

local db
local env

local drink_incr = function(network, sender, channel, message)
	incr = pcre.match(message, "([^ \\+,]+)\\+\\+")
	if incr then
		log:debug('[drinks] Incrementing ' .. incr)
		result = db:execute(
				string.format([[
					SELECT id FROM drinks WHERE name LIKE '%s'
					]], incr)
				)
		drink = result:fetch({}, "a")
		if drink then
			result = db:execute(
					string.format([[
						SELECT id FROM user WHERE name LIKE '%s'
						]], sender.nick)
					)
			user = result:fetch({}, "a")
			if not user then
				db:execute(
						string.format([[
							INSERT INTO user (name) VALUES ('%s')
							]], sender.nick)
					  )
				result = db:execute(
						string.format([[
							SELECT id FROM user WHERE name LIKE '%s'
							]], sender.nick)
						)
				user = result:fetch({}, "a")
			end
			result = db:execute(
					string.format([[
						INSERT INTO stat (time, drink, user) VALUES (datetime('now'), %d, %d)
						]], drink.id, user.id)
					)
			--log:debug("[drinks] Result: " .. result)
			if result == 1 then
				result = db:execute(
						string.format([[
							SELECT COUNT(*) FROM stat JOIN user ON stat.user = user.id WHERE user.name LIKE '%s'
							]], sender.nick)
						)
				num = result:fetch({})[1]
				network.send("privmsg", channel, sender.nick .. "hatte schon " .. num .. " " .. incr)
			else
				log:debug('[drinks] Incrementing failed')
			end
		else
			log:debug('[drinks] Drink ' .. incr .. ' does not exist.')
		end
	end
end


local interface = {
	construct = function(database)
		log:info("Loading module 'drinks'")
		env = assert(luasql.sqlite3())
		db = assert(env:connect(database))
		if not db
		then
			log:info("[drinks] Failed to load database")
			return false
		else
			log:info("[drinks] Loading database successful.")
			return true
		end
	end,

	destruct = function()
		db:close()
		env:close()
	end,

	--step = function()
		-- step() is called in configuration-dependent intervals to allow basic
		-- timeout handling.
	--end,

	authorized_handlers = {
		-- One typical IRC message handler:
		privmsg = function(network, sender, channel, message)
			drink, alc, caff = pcre.match(message, "^!drinks\.new\\(([^ \\+,]+), (\\d+), (\\d+)\\)")
			if drink then
				exists = db:execute(
					string.format([[
							SELECT name FROM drinks WHERE name LIKE '%s'
						]], '%' .. drink .. '%')
					)
				exdrink = exists:fetch({}, "a")
				--exdrinks = ""
				--while exdrink do
					--log:debug('[drinks] Exists: ' .. exdrink.name)
					--if exdrinks == "" then
						--exdrinks = exdrink.name
					--else
						--exdrinks = exdrinks .. ", " .. exdrink.name
					--end
					--exdrink = exists:fetch({}, "a")
				--end
				if exdrink then
					network.send("privmsg", channel, "A drink, similar to " .. drink .. " already exists: " .. exdrink.name)
				else
					res = db:execute(
						string.format([[
								INSERT INTO drinks (name, alcohol, caffeine) VALUES ("%s", %d, %d);
							]], drink, alc, caff)
						)
					if res == 1 then
						network.send("privmsg", channel, "New drink " .. drink .. " added to database.")
						log:info("[drinks] Added " .. drink .. " to database.")
					else
						log:info(res)
					end
				end
			else
				drink_incr(network, sender, channel, message)
			end
		end,

		
		-- There are two special non-standard handlers:
		--disconnect = function(net, wanted, err)
			-- Is called when the network connection is closed.
			-- The parameter "wanted" indicates - if set to true that the network
			-- connection was closed by a module or the user and - probably - won't
			-- come back on-line.
		--end,
		-- and
		--connected = function(net)
			-- Fairly self-explanatory.
			-- Is - currently - called once the irc network sends an
			-- "End of MOTD" message - after which the connection can be regarded as
			-- established and the server should recognize every message sent to him.
		--end
	},

	handlers = {
		privmsg = function(network, sender, channel, message)
			drink_incr(network, sender, channel, message)
		end,
	},
}

return interface
