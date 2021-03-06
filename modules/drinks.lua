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

local increment = function(user, drink)
	log:debug('[drinks] Incrementing ' .. drink)
	result = db:execute(
			string.format([[
				SELECT id FROM drinks WHERE name LIKE '%s'
				]], drink)
			)
	dbdrink = result:fetch({}, "a")
	result:close()
	if dbdrink then
		result = db:execute(
				string.format([[
					SELECT id FROM user WHERE name LIKE '%s'
					]], user)
				)
		dbuser = result:fetch({}, "a")
		result:close()
		if not dbuser then
			db:execute(
					string.format([[
						INSERT INTO user (name) VALUES ('%s')
						]], user)
				  )
			result = db:execute(
					string.format([[
						SELECT id FROM user WHERE name LIKE '%s'
						]], user)
					)
			dbuser = result:fetch({}, "a")
			result:close()
		end
		result = db:execute(
				string.format([[
					INSERT INTO stat (time, drink, user) VALUES (datetime('now'), %d, %d)
					]], dbdrink.id, dbuser.id)
				)
		--log:debug("[drinks] Result: " .. result)
		if result == 1 then
			result = db:execute(
					string.format([[
						SELECT COUNT(*) FROM stat WHERE user = %d AND drink = %d
						]], dbuser.id, dbdrink.id)
					)
			num = result:fetch({})[1]
			result:close()
			return user .. " hatte schon " .. num .. " " .. drink
		else
			log:debug('[drinks] Incrementing failed')
			return "An Error occoured."
		end
	else
		log:debug('[drinks] Drink ' .. drink .. ' does not exist.')
		return "Drink " .. drink .. " does not exist."
	end
end

local drinks_stat = function(user)
	log:debug("[drinks] Generating stats for " .. user)
	result = db:execute(
			string.format([[
				SELECT id FROM user WHERE name LIKE '%s'
				]], user)
			)
	dbuser = result:fetch({}, "a")
	result:close()
	if not dbuser then
		db:execute(
				string.format([[
					INSERT INTO user (name) VALUES ('%s')
					]], user)
			  )
		result = db:execute(
				string.format([[
					SELECT id FROM user WHERE name LIKE '%s'
					]], user)
				)
		dbuser = result:fetch({}, "a")
		result:close()
	end
	log:debug("[drinks] " .. user .. " has the id " .. dbuser.id)
	result = db:execute([[SELECT id,name FROM drinks WHERE equals ISNULL]])
	drinks = {}
	row = result:fetch({}, "a")
	while row do
		table.insert(drinks, row)
		row = result:fetch({}, "a")
	end
	result:close()
	stat = {}
	for _, drink in pairs(drinks) do
		result = db:execute(
				string.format([[
						SELECT COUNT(*) FROM stat WHERE user = %d AND drink = %d
					]], dbuser.id, drink.id)
				)
		row = result:fetch()
		while row do
			if row ~= '0' then
				table.insert(stat, drink.name .. ": " .. row)
			end
			row = result:fetch({})
		end
		result:close()
	end
	return table.concat(stat, ", ")
end

local drinks_handler = function(network, sender, channel, message)
	matches = pcre.gmatch(message, "([^ \\+,]+)\\+\\+|([^ \\+]+) ?\\+= ?(\\d+)|!drinks\.(list|stat|help)(\\([^ ]*\\))?")
	if type(matches) == "function" then
		incr, nincr, n, func, arg = matches()
		while type(incr) ~= "nil" do
			if incr ~= false then
				network.send("privmsg", channel, increment(sender.nick, incr))
			elseif nincr ~= false and n ~= false then
				if n ~= "0" then
					for i = 1, n-1, 1 do
						increment(sender.nick, nincr)
					end
					network.send("privmsg", channel, increment(sender.nick, nincr))
				else
					network.send("privmsg", channel, "Jaja...")
				end
			elseif func == "list" then
				result = db:execute([[SELECT name, amount FROM drinks]])
				drinks = {}
				row = result:fetch({}, "a")
				while row do
					table.insert(drinks, row.name .. ' [' .. row.amount .. 'l]')
					row = result:fetch(row, "a")
				end
				result:close()
				network.send("privmsg", channel, "I know the following drinks: " .. table.concat(drinks, ", "))
			elseif func == "stat" then
				if arg ~= false then
					network.send("privmsg", channel, drinks_stat(string.sub(arg, 2, string.len(arg)-1)))
				else
					network.send("privmsg", channel, drinks_stat(sender.nick))
				end
			elseif func == "help" then
				network.send("privmsg", channel, "Functions: list (list of all known drinks), stat(user) (stats of user (own stats if user is empty)), help (gives you this message), new(name, alc, caff, amount) (only for authorized user)")
			end
			incr, nincr, n, func, arg = matches()
		end
	end
end


local interface = {
	construct = function(database)
		env = assert(luasql.sqlite3())
		db = assert(env:connect(database))
		if not db
		then
			log:warning("[drinks] Failed to load database")
			return false
		else
			db:setautocommit(true)
			log:debug("[drinks] Loading database successful.")
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
			drink, alc, caff, amount = pcre.match(message, "^!drinks\.new\\(([^ \\+,]+), ?(\\d+), ?(\\d+), ?(\\d+\.?\\d{1,2})\\)")
			if drink then
				exists = db:execute(
					string.format([[
							SELECT name FROM drinks WHERE name LIKE '%s'
						]], '%' .. drink .. '%')
					)
				exdrink = exists:fetch({}, "a")
				result:close()
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
								INSERT INTO drinks (name, alcohol, caffeine, amount) VALUES ("%s", %d, %d, %d);
							]], drink, alc, caff, amount)
						)
					if res == 1 then
						network.send("privmsg", channel, "New drink " .. drink .. " added to database.")
						log:info("[drinks] Added " .. drink .. "(" alc .. ", " .. caff .. ", " .. amount ")" .. " to database.")
					else
						log:info(res)
					end
				end
			else
				drinks_handler(network, sender, channel, message)
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
			drinks_handler(network, sender, channel, message)
		end,
	},
}

return interface
