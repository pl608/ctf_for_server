local CHAT_COLOR = "orange"
local timer = nil
local bounties = {}

ctf_modebase.bounties = {}

local function get_reward_str(rewards)
	local ret = ""

	for reward, amount in pairs(rewards) do
		ret = string.format("%s%s%d %s, ", ret, amount >= 0 and "+" or "-", amount, HumanReadable(reward))
	end

	return ret:sub(1, -3)
end

local function set(pname, pteam, rewards)
	-- pname(str) is the player's name
	-- pteam(str) is the player's team(e.g. "red")
	-- rewards(table) has two entries:
	-- -- bounty_kills(int) which is usually 1
	-- -- score(int) which is the amount of score given to the one
	-- -- -- who claims the bounty
	local bounty_message = minetest.colorize(CHAT_COLOR, string.format(
		"[Bounty] %s. Rewards: %s",
		pname, get_reward_str(rewards)
	))

	for _, team in ipairs(ctf_teams.current_team_list) do -- show bounty to all but target's team
		if team ~= pteam then
			ctf_teams.chat_send_team(team, bounty_message)
		end
	end

	bounties[pteam] = {name = pname, rewards = rewards, msg = bounty_message}
end

local function remove(pname, pteam)
	minetest.chat_send_all(minetest.colorize(CHAT_COLOR, string.format("[Bounty] %s is no longer bountied", pname)))
	bounties[pteam] = nil
end

function ctf_modebase.bounties.claim(player, killer)
	local pteam = ctf_teams.get(player)

	if not (pteam and bounties[pteam] and bounties[pteam].name == player) then
		return
	end

	local rewards = bounties[pteam].rewards
	minetest.chat_send_all(minetest.colorize(CHAT_COLOR,
		string.format("[Bounty] %s killed %s and got %s", killer, player, get_reward_str(rewards))
	))

	bounties[pteam] = nil
	return rewards
end

function ctf_modebase.bounties.reassign()
	local teams = {}

	for tname, team in pairs(ctf_teams.online_players) do
		teams[tname] = {}
		for player in pairs(team.players) do
			table.insert(teams[tname], player)
		end
	end

	for tname in pairs(bounties) do
		if not teams[tname] then
			teams[tname] = {}
		end
	end

	for tname, team_members in pairs(teams) do
		local old = nil
		if bounties[tname] then
			old = bounties[tname].name
		end

		local new = nil
		if #team_members > 0 then
			new = ctf_modebase.bounties.get_next_bounty(team_members)
		end

		if old and old ~= new then
			remove(old, tname)
		end

		if new then
			set(new, tname, ctf_modebase.bounties.bounty_reward_func(new))
		end
	end
end

function ctf_modebase.bounties.reassign_timer()
	timer = minetest.after(math.random(180, 360), function()
		ctf_modebase.bounties.reassign()
		ctf_modebase.bounties.reassign_timer()
	end)
end

ctf_api.register_on_match_start(ctf_modebase.bounties.reassign_timer)

ctf_api.register_on_match_end(function()
	bounties = {}
	if timer then
		timer:cancel()
		timer = nil
	end
end)

function ctf_modebase.bounties.bounty_reward_func()
	return {bounty_kills = 1, score = 500}
end

function ctf_modebase.bounties.get_next_bounty(team_members)
	return team_members[math.random(1, #team_members)]
end

ctf_teams.register_on_allocplayer(function(player, new_team, old_team)
	local pname = player:get_player_name()

	if old_team and old_team ~= new_team and bounties[old_team] and bounties[old_team].name == pname then
		remove(pname, old_team)
	end

	local output = {}

	for tname, bounty in pairs(bounties) do
		if new_team ~= tname then
			table.insert(output, bounty.msg)
		end
	end

	if #output > 0 then
		minetest.chat_send_player(pname, table.concat(output, "\n"))
	end
end)

ctf_core.register_chatcommand_alias("list_bounties", "lb", {
	description = "List current bounties",
	func = function(name)
		local pteam = ctf_teams.get(name)
		local output = {}
		local x = 0
		for tname, bounty in pairs(bounties) do
			local player = minetest.get_player_by_name(bounty.name)

			if player and pteam ~= tname then
				local label = string.format(
					"label[%d,0.1;%s: %s score]",
					x,
					bounty.name,
					minetest.colorize("cyan", bounty.rewards.score)
				)

				table.insert(output, label)
				local model = "model[%d,1;4,6;player;character.b3d;%s;{0,160};;;]"
				model = string.format(
					model,
					x,
					player:get_properties().textures[1]
				)
				table.insert(output, model)
				x = x + 4.5
			end
		end

		if #output <= 0 then
			return false, "There are no bounties you can claim"
		end
		x = x - 1.5
		local formspec = "size[" .. x .. ",6]\n" .. table.concat(output, "\n")
		minetest.show_formspec(name, "ctf_modebase:lb", formspec)
		return true, ""
	end
})

ctf_core.register_chatcommand_alias("put_bounty", "pb", {
	description = "Put bounty on some player",
	params = "<player> <amount>",
	privs = { ctf_admin = true },
	func = function(name, param)
		local player, amount = string.match(param, "(.*) (.*)")
		local pteam = ctf_teams.get(player)
		local team_colour = ctf_teams.team[pteam].color
		if not (player and pteam and amount) then
			return false, "Incorrect parameters"
		end
		amount = ctf_core.to_number(amount)
		set(
			player,
			pteam,
			{ bounty_kills=1, score=amount }
		)
		return true, "Successfully placed a bounty of " .. amount .. " on " .. minetest.colorize(team_colour, player) .. "!"
	end,
})

local bounty_votes = {}
--bounty_votes:
--	name:
--		votes
--		amount
--		voter_name(names voters):
--			amount
--  
--this can potentialy all be shortened down to
--bounty_votes:
--	voters:
--		player_obj/player_name
--		amount


ctf_api.register_on_match_end(function()
	bounty_votes = {}
end)
--[[
minetest.register_chatcommand("vote_bounty", 'vb',{
	description = "Vote a bounty onto a player\nNeeds 5 players to add and can only vote once every 10 mins",
	params = "<playername> <score>",
	func = function(name, param)
		local current_mode = ctf_modebase:get_current_mode()
		if not current_mode or not ctf_modebase.match_started then
			return false, "The match hasn't started yet!"
		end

		local pname, score = string.match(param, "^(.*) (.*)$")
		if bounty_votes[pname] and bounty_votes[pname]['votes'] and table.contains(bounty_votes[pname]['voters'], name) then
			return false, "You can't vote a bounty on the same person more then once!"
		end
		
		if bounty_votes[pname] and bounty_votes[pname]['votes'] and bounty_votes[pname]['votes'] >= 5 then
			
			set(
				player,
				pteam,
				{ bounty_kills=1, score=bounty_votes[pname]['amount']+score }
			)
			local msg = 'Bounty on '+pname+' set by '
			for i, element in ipairs(bounty_votes[pname]['voters']) do
				msg = msg + element['name'] +'('+ element['amount']+')'
				current_mode.recent_rankings.add(element['name'], {score=-element['amount']}, true)-- You lose score even if the bounty is not fufilled... may need to fix that
			end
			minetest.chat_send_all(msg)
			return true,'Success'
		end

		bounty_votes[pname]['votes'] = (bounty_votes[pname]['votes']+1) or 1
		bounty_votes[pname]['amount'] = (bounty_votes[pname]['amount']+score) or score
		local tmp = {}
		tmp['name'] = name
		tmp['amount'] = amount
		bounty_votes[pname]['voters'] = tmp

		return true, 'Added you to the list of voters. Current stats are at: score='+bounty_votes[pname]['amount'].to_string()+', votes='+bounty_votes[pname]['votes'].to_string()
	end
})
		
		
]]
