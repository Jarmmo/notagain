local DEBUG = false
local DEBUG2 = false

local ENT = {}
local MOVED = {}
local MOVE_REF = {}

ENT.ClassName = "monster_seagull"
ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.Spawnable = true
ENT.AdminSpawnable = false
ENT.PrintName = "seagull mount"
ENT.Model = "models/seagull.mdl"

local function WRITE_COUNT(n)
	net.WriteUInt(n, 16)
end

local function READ_COUNT()
	return net.ReadUInt(16)
end

local function WRITE_ID(n)
	net.WriteUInt(n, 12)
end

local function READ_ID()
	return net.ReadUInt(12)
end

local function WRITE_VECTOR(v)
	net.WriteInt(v.x, 16)
	net.WriteInt(v.y, 16)
	net.WriteInt(v.z, 16)
end
local function READ_VECTOR(v)
	local x = net.ReadInt(16)
	local y = net.ReadInt(16)
	local z = net.ReadInt(16)
	return Vector(x,y,z)
end

local function WRITE_ANGLE(a)
	net.WriteInt(a.x, 9)
	net.WriteInt(a.y, 9)
	net.WriteInt(a.z, 9)
end

local function READ_ANGLE(a)
	local p = net.ReadInt(9)
	local y = net.ReadInt(9)
	local r = net.ReadInt(9)

	return Angle(p,y,r)
end

function ENT:SetScale(scale)
	self.scale = scale

	if SERVER then
		self:PhysicsInitSphere(scale, "gmod_ice")
		self:GetPhysicsObject():SetMass(scale * 20)
		self:SetCollisionBounds( Vector( -scale, -scale, -scale ) , Vector( scale, scale, scale ) )

		self:SetCollisionGroup(COLLISION_GROUP_INTERACTIVE_DEBRIS)
	end
end

function ENT:GetScale()
	return self.scale
end


function ENT:InAir()
	if not self.next_in_air or self.next_in_air < RealTime() then
		local point = self:GetPos()
		local down = -self:GetUp()
		local down_dir = down * self:GetScale()*1.7

		if bit.band(util.PointContents(point + down_dir), CONTENTS_SOLID ) == CONTENTS_SOLID then
			self.in_air = false
		else
			self.tr_out = self.tr_out or {}
			self.tr_in = self.tr_in or {output = self.tr_out}

			if CLIENT then
				self.tr_in.start = point - down
				self.tr_in.endpos = point + down_dir

				util.TraceLine(self.tr_in)
			else
				point = point + down

				self.tr_in.start = point
				self.tr_in.endpos = point


				util.TraceEntity(self.tr_in, self)

				if self.tr_out.Entity.ClassName == ENT.ClassName then
					self.tr_out.Hit = false
				end
			end

			self.in_air = not self.tr_out.Hit
		end

		self.next_in_air = RealTime() + 0.1
	end

	return self.in_air
end

function ENT:GetGroundTrace(distance)
	distance = distance or 15
	self.ground_trace_cache[distance] = self.ground_trace_cache[distance] or {}

	if self.ground_trace_cache[distance].next and self.ground_trace_cache[distance].next > RealTime() then
		return self.ground_trace_cache[distance].res
	end

	local gravity_dir = physenv.GetGravity():GetNormalized()
	local bottom = self:GetPos() + gravity_dir * (self:GetScale() * 1.7)
	local info = {
		start = self:GetPos(),
		endpos =  bottom + gravity_dir * distance,
		filter = {self},
	}

	local res = util.TraceLine(info)

	--debugoverlay.Line(bottom, res.HitPos, 0, nil, true)

	self.ground_trace_cache[distance].res = res
	self.ground_trace_cache[distance].next = RealTime() + 0.2

	return res
end

if CLIENT then
	ENT.Cycle = 0
	ENT.Noise = 0

	ENT.Animations = {
		Fly = "Fly",
		Run = "run",
		Walk = "walk",
		Idle = "idle01",
		Soar = "soar",
		Land = "land",
		Takeoff = "takeoff",
	}

	local sounds = {
		"npc/fast_zombie/foot2.wav",
	}
	for i = 1, 5 do
		sounds[i] = "seagull_step_" .. i .. "_" .. util.CRC(os.clock())
		sound.Generate(sounds[i], 22050, 0.25, function(t)
			local f = (t/22050) * (1/0.25)
			f = -f + 1
			f = f ^ 10
			return ((math.random()*2-1) * math.sin(t*1005) * math.cos(t*0.18)) * f
		end)
	end

	local ambient_sounds = {
		"ambient/creatures/seagull_idle1.wav",
		"ambient/creatures/seagull_idle2.wav",
		"ambient/creatures/seagull_idle3.wav",
	}

	function ENT:Update()
		self:AnimationThink()

		local scale = self:GetScale()
		if scale ~= self.last_scale then
			self:SetColor(Color(255, 255, Lerp(scale/20, 100, 255), 255))
			self:SetModelScale(scale / self:GetModelRadius() * 6)
			self.local_pos = Vector(0, 0, -scale)

			self.last_scale = scale
		end

		if math.random() > 0.99 then
			sound.Play(ambient_sounds[math.random(1, #ambient_sounds)], self.pos, 75, math.Clamp((1000 / scale) + math.Rand(-10, 10), 1, 255), 1)
		end
	end

	function ENT:SetAnim(anim)
		self:SetSequence(self:LookupSequence(self.Animations[anim]))
	end

	function ENT:AnimationThink()
		local scale = self:GetScale()

		local vel = self.vel / scale
		local len = vel:Length()
		local siz = scale*0.05
		len = len / siz

		if not self:InAir() then
			self.takeoff = false

			local mult = 1

			if len < 1 / siz then
				self:SetAnim("Idle")
				len = 15 / siz * (self.Noise * 0.25)
			else
				if CLIENT then
					self:StepSoundThink()
				end

				if len > 50 / siz then
					self:SetAnim("Run")
				else
					self:SetAnim("Walk")
				end
				mult = math.Clamp(self:GetForward():Dot(vel), -1, 1)
			end

			self.Noise = (self.Noise + (math.Rand(-1,1) - self.Noise) * FrameTime())
			self.Cycle = (self.Cycle + (len / (2.5 / siz)) * FrameTime() * mult) % 1
			self:SetCycle(self.Cycle)
		else

			local ground = self:GetGroundTrace(self:BoundingRadius() - 4)

			if ground.Fraction < 1 then
				local f = ground.Fraction
				if vel.z > 0 then
					if not self.takeoff then
						self:SetAnim("Takeoff")
						f = Lerp(f, 0.3, 0.4)
					end
				else
					f = Lerp(f, 0.5, 0.8)
					self:SetAnim("Land")
				end

				self:SetCycle(f)
				return
			else
				self.takeoff = true
			end

			if len < 50 then
				self:SetAnim("Fly")
				self.Cycle = self.Cycle + FrameTime() * 3.5 * (math.Rand(1, 1.1))
			else

				local fvel = self:GetRight():Dot(self.vel)
				if math.abs(fvel) > 50 then
					self:SetAnim("Fly")
					self.Cycle = self.Cycle + FrameTime() * 0.5 * (math.Rand(1, 1.1))
				else

					if vel.z < 0 then
						self:SetAnim("Soar")
						self.Cycle = math.random()
					else
						self:SetAnim("Fly")

						if vel.z > 0 then
							self.Cycle = self.Cycle + FrameTime() * 2
						else
							self.Cycle = Lerp(math.Clamp((-vel.z/100), 0, 1), 0.1, 1)
						end
					end
				end
			end

			self:SetCycle(self.Cycle)
		end
	end

	function ENT:StepSoundThink() do return end
		local siz = self:GetScale()
		local stepped = self.Cycle%0.5
		if stepped  < 0.3 then
			if not self.stepped then
				--[[sound.Play(
					table.Random(sounds),
					self:GetPos(),
					math.Clamp(10 * siz, 70, 160),
					math.Clamp(100 / (siz/3) + math.Rand(-20,20), 40, 255)
				)]]

				EmitSound(
					table.Random(sounds),
					self:GetPos(),
					self:EntIndex(),
					CHAN_AUTO,
					1,
					--math.Clamp(10 * siz, 70, 160),
					55,
					0,
					--math.Clamp(100 / (siz/3) + math.Rand(-20,20), 40, 255)
					math.Clamp(700/siz + math.Rand(-15, 15), 10, 255)
				)

				self.stepped = true
			end
		else
			self.stepped = false
		end
	end


	local seagulls = _G.SEAGULLS_ENTS or {}
	local seagullsi = _G.SEAGULLS_ENTSI or {}

	_G.SEAGULLS_ENTS = seagulls
	_G.SEAGULLS_ENTSI = seagullsi

	net.Receive("seagull_create", function()
		local id = READ_ID()
		local scale = net.ReadFloat()

		local self = ClientsideModel(ENT.Model)
		self:SetParent(self)
		self:SetLOD(0)
		self.scale = scale
		self.vel = Vector()
		self.pos = Vector()
		self.ang = Angle()
		self.local_pos = Vector()
		self.seagull_id = id

		for k,v in pairs(ENT) do
			self[k] = v
		end

		self.ground_trace_cache = {}
		self.standing_still = true

		seagulls[id] = self
		table.insert(seagullsi, self)
	end)

	net.Receive("seagull_update", function()
		local count = READ_COUNT()
		for i = 1, count do
			local id = READ_ID()
			local self = seagulls[id]
			if not self then return end

			local pos = READ_VECTOR()
			local ang = READ_ANGLE()

			self.pos = pos
			self.ang = ang
		end
	end)

	net.Receive("seagull_remove", function()
		local id = READ_ID()

		local self = seagulls[id]
		self:Remove()
	end)

	hook.Add("Think", "seagulls", function()
		local dt = math.Clamp(FrameTime() * 5, 0.0001, 1)
		for i = 1, #seagullsi do
			local self = seagullsi[i]

			if self:IsValid() then

				local last_pos = self.smooth_pos or self.pos

				self.smooth_pos = self.smooth_pos or self.pos
   				self.smooth_pos = self.smooth_pos + ((self.pos - self.smooth_pos) * dt)

				self.vel = (self.smooth_pos - last_pos) * 50

				self.smooth_dir = self.smooth_dir or self.ang:Forward()
				self.smooth_dir = self.smooth_dir + ((self.ang:Forward() - self.smooth_dir) * dt)

				self:SetPos(self.smooth_pos + self.local_pos)
				self:SetAngles(self.smooth_dir:Angle())

				ENT.Update(self)
			end
		end
	end)
end

if SERVER then
	util.AddNetworkString("seagull_create")
	util.AddNetworkString("seagull_remove")
	util.AddNetworkString("seagull_update")

	SEAGULL_ID = 0

	function ENT:Initialize()
		local scale = math.Rand(15,25)

		self:SetScale(scale)

		self.ground_trace_cache = {}
		self.standing_still = true

		self.seagull_id = SEAGULL_ID

		net.Start("seagull_create")
		net.WriteUInt(self.seagull_id, 12)
		net.WriteFloat(scale)
		net.Broadcast()

		SEAGULL_ID = SEAGULL_ID + 1
	end

	function ENT:OnRemove()
		SafeRemoveEntity(self.weld)

		net.Start("seagull_remove")
		net.WriteUInt(self.seagull_id, 12)
		net.Broadcast()
	end
end

if SERVER then
	local temp_vec = Vector()
	local function VectorTemp(x,y,z)
		temp_vec.x = x
		temp_vec.y = y
		temp_vec.z = z
		return temp_vec
	end

	local flock_radius = 2000

	local flock_pos
	local food = {}
	local tallest_points = {}
	local all_seagulls = ents.FindByClass(ENT.ClassName)

	local function global_update()
		all_seagulls = ents.FindByClass(ENT.ClassName)

		local found = all_seagulls
		local count = #found
		local pos = VectorTemp(0,0,0)

		for _, ent in ipairs(found) do
			local p = ent.Position or ent:GetPos()
			pos = pos + p
		end

		if count > 1 then
			pos = pos / count

			flock_vel = (flock_pos or pos) - pos

			flock_pos = pos

			if DEBUG then
				debugoverlay.Sphere(pos, flock_radius, 1, Color(0, 255, 0, 5))
				if me:KeyDown(IN_JUMP) then
					tallest_points = {}
				end
			end

			local up = physenv.GetGravity():GetNormalized()
			local top = util.QuickTrace(pos + Vector(0,0,flock_radius/2), up*-10000).HitPos
			top.z = math.min(pos.z + flock_radius, top.z)
			local bottom = util.QuickTrace(top, up*10000).HitPos

			if DEBUG then
				debugoverlay.Text(top, "TOP", 1)
				debugoverlay.Text(bottom, "BOTTOM", 1)
				debugoverlay.Text(LerpVector(0.5, top, bottom), "POINTS: " .. #tallest_points, 1)
			end

			top.z = math.min(flock_pos.z + flock_radius, top.z)

			local max = 30

			if not tallest_points[max] then
				for i = 1, max do
					if tallest_points[max] then
						break
					end

					local start_pos = LerpVector(i/max, bottom, top)

					if DBEUG then
						debugoverlay.Cross(start_pos, 100, 1)
					end

					--if not util.IsInWorld(start_pos) then break end
					local tr = util.TraceLine({
						start = start_pos,
						endpos = start_pos + VectorTemp(math.Rand(-1, 1), math.Rand(-1, 1), math.Rand(-1, -0.2))*flock_radius,
					})

					if tr.Hit and math.abs(tr.HitNormal.z) > 0.8 and (not tr.Entity:IsValid() or tr.Entity.ClassName ~= ENT.ClassName) then
						if tr.HitPos.z > flock_pos.z then
							for _,v in ipairs(tallest_points) do
								if v:Distance(tr.HitPos) < 50 then
									return
								end
							end

							table.insert(tallest_points, tr.HitPos)
						end
					end

					if DEBUG then
						debugoverlay.Line(tr.StartPos, tr.HitPos, 1, tr.Hit and Color(0,255,0, 255) or Color(255,0,0, 255))
					end
				end

				if DEBUG then
					for _,v in ipairs(tallest_points) do
						debugoverlay.Cross(v, 5, 1, Color(0,0,255, 255))
					end
				end

				table.sort(tallest_points, function(a, b) return a.z > b.z end)

				for i = #tallest_points, 1, -1 do
					local v = tallest_points[i]
					if v:Distance(flock_pos) > flock_radius then
						table.remove(tallest_points, i)
					end
				end
			end
		else
			flock_pos = nil
		end
	end

	local function entity_create(ent)
		timer.Simple(0.25, function()
			if not ent:IsValid() then return end

			local phys = ent:GetPhysicsObject()
			if phys:IsValid() and (
				phys:GetMaterial():lower():find("flesh") or
				phys:GetMaterial() == "watermelon" or
				phys:GetMaterial() == "antlion"
			) then
				ent.seagull_food = true
				table.insert(food, ent)
			end
		end)
	end

	local function entity_remove(ent)
		if ent.seagull_food then
			for i,v in ipairs(food) do
				if v == ent then
					table.remove(food, i)
				end
			end
		end
	end

	function ENT:OnTakeDamage(info)
		print(self, info:GetDamage(), info:GetAttacker())
	end

	timer.Create(ENT.ClassName, 1, 0, function()
		global_update()
	end)

	hook.Add("OnEntityCreated", ENT.ClassName, function(ent)
		entity_create(ent)
	end)

	hook.Add("EntityRemoved", ENT.ClassName, function(ent)
		entity_remove(ent)
	end)

	function ENT:Think()
		if DEBUG2 then
			if me:KeyDown(IN_ATTACK) then
				self:MoveTo({
					pos = me:GetEyeTrace().HitPos,
					priority = 1,
					id = "test"
				})
			end

			if me:KeyDown(IN_RELOAD) then
				for _,v in ipairs(all_seagulls) do
					v:Remove()
				end
			end

			if me:KeyDown(IN_ATTACK2) then
				self:CancelMoving()
			end

			if me:KeyDown(IN_DUCK) then
				if tallest_points[1] then
					local point = table.remove(tallest_points, 1)

					self.tallest_point_target = point
					self:MoveTo({
						pos = point,
					})
				end
			end
		end

		if flock_pos then

			if not self.tallest_point_target or (self.reached_target and math.random() > 0.2 and self.tallest_point_target.z < flock_pos.z - 100) then
				if tallest_points[1] then
					local point = table.remove(tallest_points, 1)

					self.tallest_point_target = point
					self:MoveTo({
						pos = point,
					})
				end
			end

			if math.random() > 0.9 and flock_pos:Distance(self:GetPos()) > flock_radius then
				self:MoveTo({
					get_pos = function()
						return flock_pos
					end,
					check = function()
						return flock_pos:Distance(self:GetPos()) > flock_radius
					end,
					id = "flock",
				})
			end

		end

		if math.random() > 0.9 and not self.finding_food and not IsValid(self.weld) then
			local ent = food[math.random(1, #food)] or NULL
			if ent:IsValid() then
				self.finding_food = true

				local radius = self:BoundingRadius()
				self:MoveTo({
					check = function()
						return
						ent:IsValid() and
						(
							not IsValid(ent.seagull_weld) or
							not IsValid(ent.seagull_weld.seagull) or
							(ent.seagull_weld.seagull ~= self and ent.seagull_weld.seagull:GetScale() < self:GetScale())
						)
					end,
					get_pos = function()
						return ent:GetPos()
					end,
					priority = 1,
					id = "food",
					fail = function()
						self.finding_food = nil
					end,
					finish = function()
						self.finding_food = nil

						local s = self:GetScale()
						ent:SetPos(self:GetPos() + self:GetForward() * (s + 2) + self:GetUp() * s)
						ent:GetPhysicsObject():EnableMotion(true)

						local weld = constraint.Weld(self, ent, 0, 0, radius*500, true, false)

						if weld then

							ent:SetOwner(self)

							self.weld = weld
							self.weld.seagull = self
							self.food = ent

							ent.seagull_weld = weld
						end
					end,
				})
			end
		end


		local phys = self:GetPhysicsObject()

		local fps = 10

		self:PhysicsUpdate2(phys, 6)

		if not self:InAir() and self.VelocityLength < 1 then
			phys:Sleep()
		end

		self:CalcMoveTo()

		local updatedPos = false

		if self.LastStoredPos ~= self:GetPos() then
			self.LastStoredPos = self:GetPos()
			updatedPos = true
		end

		if self.LastStoredAng ~= self:GetAngles() then
			self.LastStoredAng = self:GetAngles()
			updatedPos = true
		end

		if updatedPos == true then
			local tableId = #MOVED + 1
			local data = MOVE_REF[self.seagull_id]
			if data ~= nil then
				data[2] = self:GetPos()
				data[3] = self:GetAngles()
				--print("Updating move record")
			else
				-- Insert new queue record, keep order.
				table.insert(MOVED, { self.seagull_id, self:GetPos(), self:GetAngles(), tableId } )
				MOVE_REF[self.seagull_id] = MOVED[tableId]
				--print("Added move record")
			end
		else
			--print("No update")
		end

		self:NextThink(CurTime() + 1/fps)
		return true
	end

	function ENT:AvoidOthers()
		if not self.next_avoid or self.next_avoid < self.Time then
			self.next_avoid = self.Time + math.random()*3

			local pos = self.Position
			local in_air = self:InAir()
			local radius = self.Radius * (in_air and 5 or 2)
			local average_pos = Vector()
			local count = 0

			for _, v in ipairs(all_seagulls) do
				local pos2 = v.Position or v:GetPos()
				--local radius2 = v.Radius or v:BoundingRadius()

				if ((in_air and v:InAir()) or (not in_air and not v:InAir())) and pos2:Distance(pos) < (radius) then
					average_pos = average_pos + pos2
					count = count + 1
				end
			end
			if count > 1 then
				average_pos = average_pos / count

				local vel = pos - average_pos

				local len = vel:Length()

				if len < 5 then return end

				if not in_air then
					vel.z = 0
				end
				if self.TargetPosition then
					vel = vel * 0.5
				else
					self.damping_pause = self.damping_pause or 1
				end
				vel = vel * 1/len*10

				self.NewVelocity = self.NewVelocity + vel

				self.Velocity = self.NewVelocity
				self.VelocityLength = self.Velocity:Length()
			end
		end
	end

	do -- move to a point
		function ENT:MoveTo(data)
			if data.check and not data.check() then if data.fail then data.fail() end return end

			self.TargetPositions = self.TargetPositions or {}
			self.reached_target = nil
			self.target_ids = self.target_ids or {}

			data.priority = data.priority or #self.TargetPositions + 1
			local id = data.id

			if id and self.target_ids[id] then
				table.Merge(self.target_ids[id], data)
				for i,v in ipairs(self.TargetPositions) do
					if v.id == id then
						table.insert(self.TargetPositions, data.priority, table.remove(self.TargetPositions, i))
						break
					end
				end
				return
			end

			table.insert(self.TargetPositions, data.priority, data)

			if id then
				self.target_ids[id] = data
			end
		end

		function ENT:CalcMoveTo()
			if not self.TargetPositions then return end

			local info = self.TargetPositions[1]

			if info then
				local ok = not info.check or info.check(self)

				if ok then
					local pos = info.pos

					if info.get_pos then
						pos = info.get_pos(self)
					end

					local dir = pos - self.Position
					local len = dir:Length()

					if len > self.Radius then
						self.TargetPosition = pos
						self.reached_target = nil
						self.standing_still = nil
					elseif (self.VelocityLength < 100 and self.AngleVelocityLength < 100) then
						if info.waiting_time then
							self.standing_still = self.standing_still or self.Time + info.waiting_time
						end
						if not info.waiting_time or (self.standing_still < self.Time) then
							self.TargetPosition = nil
							self.standing_still = true

							table.remove(self.TargetPositions, 1)

							if info.id then
								self.target_ids[info.id] = nil
							end

							self.reached_target = true

							if info.finish then
								info.finish()
							end
						end
					end
				else
					if info.fail then
						info.fail()
					end

					table.remove(self.TargetPositions, 1)

					if info.id then
						self.target_ids[info.id] = nil
					end

					self.TargetPosition = nil
					self.reached_target = true
					self.standing_still = true
				end
			end
		end

		function ENT:CancelMoving()
			self.TargetPositions = {}

			local info = self.TargetPositions[1]

			if info then
				if info.fail then info.fail() end
			end

			self.target_ids = {}
			self.TargetPosition = nil
			self.reached_target = true
			self.standing_still = true
		end
	end

	function ENT:CalcStuck()
		if not self.standing_still then
			if not self.unstuck_timer and self.VelocityLength < 20 then
				if DEBUG then
					debugoverlay.Text(self.Position, "STUCK?", 0.1)
				end

				self.stuck_timer = self.stuck_timer or self.Time + math.Rand(0.5,1)

				if self.stuck_timer < self.Time then
					self.Stuck = true
					if DEBUG then
						debugoverlay.Text(self.Position, "STUCK ", 1)
					end
					self.unstuck_timer = self.unstuck_timer or self.Time + math.Rand(0.5,1)
				end
			else
				self.stuck_timer = nil
			end

			if self.unstuck_timer and self.unstuck_timer < self.Time then
				self.Stuck = false
				self.stuck_timer = nil
				self.unstuck_timer = nil

				if DEBUG then
					debugoverlay.Text(self.Position, "UNSTUCK!", 1)
				end
			end

			if self.Stuck then
				self:GetPhysicsObject():AddVelocity(VectorRand() * 50)
				return
			end
		end
	end


	function ENT:CalcUpright()
		local len = self.VelocityLength
		local desired_ang = self.Velocity:Angle()
		local ang = self.Physics:GetAngles()

		local p = math.AngleDifference(desired_ang.p, ang.p)/180
		local y = math.AngleDifference(desired_ang.y, ang.y)/180
		local r = math.AngleDifference(desired_ang.r, ang.r)/180

		local force = math.min(self:GetPhysicsObject():GetMass() * 0.5, 500)

		if not self:InAir() then
			force = force * math.Clamp(len-1, 0, 1)

			if force == 0 then
				self.Physics:SetAngles(Angle(0,ang.y,0))
			end
		end

		self.NewAngleVelocity = Vector(force*r, force*p, force*y)
	end

	function ENT:CalcTargetPosition()
		if self.TargetPosition then
			if DEBUG then
				debugoverlay.Line(self.TargetPosition, self.Position, 0)
			end

			self:PhysWake()

			local vel = self.TargetPosition - self.Position
			local len = self.VelocityLength

			vel:Normalize()
			vel = vel * self.Physics:GetMass()/20

			if self:InAir() then
				vel.z = vel.z + self.Physics:GetMass()*0.01
			end

			if math.abs(vel.z) < 10 and not self:InAir() then
				if len > 1000 then
					vel.z = vel.z + 10
				end
			end

			if vel.z > 0 then
				vel.z = vel.z * 5
			else
				vel.z = vel.z * 0.5
			end

			self.NewVelocity = self.NewVelocity + vel

			self.Velocity = self.NewVelocity
			self.VelocityLength = self.NewVelocity:Length()
		end
	end

	function ENT:CalcDamping()
		-- damping
		if self:InAir() then
			-- slow down before hitting the ground
			if self.Velocity.z < 0 and self:GetGroundTrace(5).Hit then
				self.Physics:SetDamping(2, 0)
			else
				self.Physics:SetDamping(1, 0)
			end
		else
			local mult = 1

			if self.damping_pause then
				self.damping_pause = math.max(self.damping_pause - FrameTime() * 1.5, 0)
				mult = -self.damping_pause+1
				if self.damping_pause == 0 then self.damping_pause = nil end
				mult = mult ^ 5
			end

			self.Physics:SetDamping(5*mult, 5*mult)
		end

		--self.NewAngleVelocity = self.NewAngleVelocity + (-self.AngleVelocity * 0.05)
	end

	function ENT:PhysicsUpdate2(phys, mult)
		self.Physics = phys
		self.Velocity = phys:GetVelocity()
		self.NewVelocity = Vector()
		self.VelocityLength = self.Velocity:Length()

		self.AngleVelocity = phys:GetAngleVelocity()
		self.NewAngleVelocity = Vector()
		self.AngleVelocityLength = self.AngleVelocity:Length()

		self.Position = phys:GetPos()
		self.Radius = self:BoundingRadius()
		self.Time = RealTime()

		self:AvoidOthers()
		self:CalcTargetPosition()
		self:CalcUpright()
		--self:CalcAir()
		self:CalcStuck()

		self:CalcDamping()

		phys:AddVelocity(self.NewVelocity * mult)
		phys:AddAngleVelocity(-self.AngleVelocity + (self.NewAngleVelocity * mult))
	end

	function ENT:UpdateTransmitState()
		return TRANSMIT_NEVER
	end

	hook.Add("Think", "seagull_update", function()
		local available = math.min(table.Count(MOVED), 10)
		if available == 0 then
			return
		end
		net.Start("seagull_update", true)
		WRITE_COUNT(available)
		local centerPos = Vector(0, 0, 0)
		for i = 1, available do
			local data = MOVED[1]

			WRITE_ID(data[1])
			WRITE_VECTOR(data[2])
			WRITE_ANGLE(data[3])

			centerPos = centerPos + data[2]
			MOVE_REF[data[1]] = nil

			table.remove(MOVED, 1)
		end
		net.SendPVS(centerPos / available)
	end)
end

scripted_ents.Register(ENT, ENT.ClassName, true)

function CREATESEAGULLS(where, max)
	for _ = 1, max or 30 do
		local ent = ents.Create("monster_seagull")
		ent:SetPos(where + Vector(math.Rand(-1,1), math.Rand(-1,1), 0)*100 + Vector(0,0,50))
		ent:Spawn()
	end
end

for _, ent in ipairs(ents.GetAll()) do
	if ent.seagull_id then
		if CLIENT then
			for k,v in pairs(ENT) do
				ent[k] = v
			end
		end
	end
end