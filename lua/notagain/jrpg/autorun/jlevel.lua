jlevel = jlevel or {}

function jlevel.GetStats(ent)
	return {
		xp = ent:GetNWInt("jlevel_xp", 0),
		xp_next_level = ent:GetNWInt("jlevel_next_level", 0),
		level = ent:GetNWInt("jlevel_level", 0),
		attribute_points = ent:GetNWInt("jlevel_attribute_points", 0),
	}
end

if SERVER then

	function jlevel.GiveXP(ent, xp)
		local level = ent:GetNWInt("jlevel_level", 0)
		local next_level = 500 * level ^ 1.5

		ent:SetNWInt("jlevel_next_level", next_level)

		if ent:GetNWInt("jlevel_xp", 0) + xp >= next_level then
			ent:SetNWInt("jlevel_level", ent:GetNWInt("jlevel_level", 0) + 1)
			ent:SetNWInt("jlevel_attribute_points", ent:GetNWInt("jlevel_attribute_points", 0) + 1)
			jlevel.GiveXP(ent, xp - next_level)
			xp = math.max(xp - next_level, 0)
			ent:EmitSound("garrysmod/save_load"..math.random(1,4)..".wav")
		end

		ent:SetNWInt("jlevel_xp", ent:GetNWInt("jlevel_xp", 0) + xp)

		if ent:IsPlayer() then
			ent:SetPData("jlevel_xp", ent:GetNWInt("jlevel_xp", 0))
			ent:SetPData("jlevel_level", ent:GetNWInt("jlevel_level", 0))
			ent:SetPData("jlevel_attribute_points", ent:GetNWInt("jlevel_attribute_points", 0))
		end
	end

	hook.Add("EntityTakeDamage", "jlevel", function(victim, dmginfo)
		local attacker = dmginfo:GetAttacker()

		if attacker:IsPlayer() then
			local dmg = dmginfo:GetDamage()
			victim.jlevel_attackers = victim.jlevel_attackers or {}

			victim.jlevel_attackers[attacker] = (victim.jlevel_attackers[attacker] or 0) + math.min(dmg, victim:GetMaxHealth())
		end
	end)

	hook.Add("EntityRemoved", "jlevel", function(ent)
		if not ent:IsNPC() or ent:Health() > 0 then return end

		if ent.jlevel_attackers then
			for attacker, dmg in pairs(ent.jlevel_attackers) do
				if attacker:IsValid() and attacker:IsPlayer() and dmg ~= 0 then
					local xp = math.min(dmg, ent:GetMaxHealth())
					jlevel.GiveXP(attacker, xp)
					hitmarkers.ShowXP(ent, xp)
				end
			end
		end
	end)

	hook.Add("PlayerInitialSpawn", "jlevel", function(ply)
		ply:SetNWInt("jlevel_xp", ply:GetPData("jlevel_xp"))
		ply:SetNWInt("jlevel_level", ply:GetPData("jlevel_level"))
		ply:SetNWInt("jlevel_attribute_points", ply:GetPData("jlevel_attribute_points"))

		ply:SetNWInt("jlevel_next_level", 500 * ply:GetNWInt("jlevel_level", 0) ^ 1.5)
	end)
end