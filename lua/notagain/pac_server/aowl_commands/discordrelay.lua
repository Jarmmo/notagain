if SERVER then
    if discordrelay then
        aowl.AddCommand({"relay","discordrelay"}, function(ply,_,com,arg,mod)
            if com == "reload" then
                discordrelay.reload()
            elseif com == "status" then
                local modulesc = table.Count(discordrelay.modules)
                local is_fetching = timer.Exists("DiscordRelayFetchMessages")
                discordrelay.log("Status:","fetching messages:",is_fetching and "yes" or "no")
                discordrelay.log("Status:",modulesc,"modules loaded.")
            elseif com == "modules" then
                if arg == "list" then
                    local str = ""
                    local modules = discordrelay[com]
                    local modulesc = table.Count(modules)
                    local i = 0
                    for name,_ in pairs(modules) arg
                        i = i + 1
                        str = str..name..(i==modulesc) and "" or " ,"
                    end
                    discordrelay.log(1,"[aowl]",com..":",str)
                elseif arg == "remove" or arg == "delete" or arg == "disable" then
                    if not mod then return false,"No Module/Extension specified!" end
                    if not discordrelay[com][mod] then return false,"Invalid Module/Extension" end
                    discordrelay[com][mod].Remove()
                elseif arg == "reload" or arg == "init" then
                    if not mod then return false,"No Module/Extension specified!" end
                    if not discordrelay[com][mod] then return false,"Invalid Module/Extension" end
                    discordrelay[com][mod].Init()
            end
            -- todo: add more commands?
		end,"developers")
	end
end