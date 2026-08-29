-- CREATED BY VANYANIK - ROBLOX IVANIKO_. - DISCORD

--[[
	client-side unit class module script
	used in a roguelike prototype,
	designed for low update cost, allowing to spawn and render
	dozens of units on screen without lag
]]

--!native
--!optimize 2

local TweenService = game:GetService("TweenService")
-- on hit effect tween
local tween_info = TweenInfo.new(.5)
local property_table = {FillTransparency = 1}

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local globals = require(ReplicatedStorage.shared.globals)
local event = require(ReplicatedStorage.shared.event)
--serdes
local reader = require(ReplicatedStorage.shared.binary.reader)
local codecs = require(ReplicatedStorage.shared.binary.codecs)
--oop replication stuff
local classes_ids = require(ReplicatedStorage.shared.id.classes_ids)
-- sparse set implementation
-- so every classes data structure is an array
-- for fast iteration and with O(1) add/read/delete time
local sparse_set = require(ReplicatedStorage.shared.sparse_set.sparse_set)
local classes_sparse_set = require(ReplicatedStorage.shared.sparse_set.classes_sparse_set)

-- remote events wrapper
local message = require(ReplicatedStorage.client.message)
-- superclass
local class = require(ReplicatedStorage.client.classes.classes_registry.templates.class)

local get_animation = require(script.get_animation)
local weapons = require(script.child_classes.weapons)

-- creating highlights prefabs
local highlights = {}
local highlights_available = 255
local highlights_folder = Instance.new("Folder")
highlights_folder.Name = "highlights"
highlights_folder.Parent = script

local models_folder = Instance.new("Folder")
models_folder.Name = "units"
models_folder.Parent = workspace

for i=1, highlights_available do
	local highlight = Instance.new("Highlight")
	highlight.OutlineTransparency = 1
	highlight.FillTransparency = 1
	highlight.OutlineColor = Color3.new(1,1,1)
	highlight.FillColor = Color3.new(1,1,1)
	highlight.Enabled = false
	highlights[i] = highlight
	highlight.Parent = highlights_folder
end

local unit = {}
-- required for proper replication
unit.class_id = classes_ids.unit

-- sparse set for this class type specifically
local set = classes_sparse_set[unit.class_id]

-- transform update variables
local lerp_t = 0
-- treating all the transform data as SoA
-- so its as cheap as i can get
local parts_list = {}
local cf_start_list = {}
local cf_goal_list = {}
local cf_list = {}
local units_list = {}
local list_i = 0

-- t is a class data
-- sent from the server
function unit.new(t)
	local self = class.new(t)
	
	-- both of them are v2's
	self.position = t.position
	self.direction = t.direction

	self.speed = t.speed

	self.health = t.health
	self.health_max =  t.health_max
	
	-- handling inventory
	self.weapons_max = t.weapons_max
	self.weapons_current = t.weapons_current
	self.weapons = {}
	self.weapons_slots = {}
	for i=1, t.weapons_current do
		local weapon_id = t["weapon_id"..i]
		local weapon = weapons.list[weapon_id]

		weapon.new(self)

	end
	
	-- mostly for items effects
	self.walking_changed = event.new()
	self.damage_applied = event.new()

	self.model = nil
	self.highlight = nil
	self.animator = nil
	-- position height is stored separatly
	self.y_offset = 0
	-- transform data index
	self.list_i = 0

	self.animations = {}

	self.walking = t.walking
	self.local_unit = false
	
	-- so it can later be easily accessed
	-- outside of the script as well
	sparse_set.add(
		set,
		self.id,
		self
	)

	return self
end

-- update unit's height
-- even tho transform update is interpolating
-- height update must be immediate
function unit.set_y_offset(self, y_offset)
	
	self.y_offset = y_offset
	
	local list_i = self.list_i
	
	local old_cf_start = cf_start_list[list_i]
	local old_cf_goal = cf_goal_list[list_i]
	
	cf_start_list[list_i] = 
		CFrame.new(
			old_cf_start.X,
			y_offset,
			old_cf_start.Z
		)
	cf_goal_list[list_i] = 
		CFrame.new(
			old_cf_goal.X,
			y_offset,
			old_cf_goal.Z
		)
	
end

function unit.set_walking(self, walking)
	if self.walking == walking then return end
	self.walking = walking
	event.fire(self.walking_changed, self.walking)
end

-- preloading highlights and assigning them on the go 
function unit.assign_highlight(self)
	if highlights_available == 0 then return end

	local highlight = highlights[highlights_available]
	highlights[highlights_available] = nil
	highlights_available -= 1

	self.highlight = highlight
	self.highlight.Enabled = true
	self.highlight.Adornee = self.model
end

-- mostly used for damge effect
function unit.highlight(self)
	if not self.highlight then return end

	self.highlight.FillTransparency = .25
	TweenService:Create(self.highlight, tween_info, property_table):Play()

end

-- doing a setter method for this
-- for a nice single line api
function unit.assign_model(self, model)
	self.model = model
	self.model.Parent = models_folder
	unit.assign_model_update(self)
end

-- add units to the
-- transform list update
function unit.assign_model_update(self)
	if not self.model then return end
	if self.list_i ~= 0 then return end
	
	-- transform update using cframe
	-- to offset unit model
	local cf =
		CFrame.lookAlong(
			Vector3.new(
				self.position.X,
				0,
				self.position.Y
			),
			Vector3.new(
				self.direction.X,
				0,
				self.direction.Y
			)
		)

	list_i += 1 -- units index in the transform update
	parts_list[list_i] = self.model.PrimaryPart -- unit's parts to offset
	cf_start_list[list_i] = cf -- their previous position
	cf_goal_list[list_i] = cf -- their goal
	cf_list[list_i] = cf -- their current position
	units_list[list_i] = self -- class instance
	
	self.list_i = list_i
	
end

-- remove units from the
-- transform list update
function unit.unassign_model_update(self)

	local index = self.list_i
	-- if not found
	-- early return
	if index == 0 then
		return
	end

	local last = list_i
	
	-- swap remove
	if index ~= last then

		parts_list[index] = parts_list[last]
		cf_start_list[index] = cf_start_list[last]
		cf_goal_list[index] = cf_goal_list[last]
		cf_list[index] = cf_list[last]

		local moved = units_list[last]
		units_list[index] = moved
		moved.list_i = index

	end

	parts_list[last] = nil
	cf_start_list[last] = nil
	cf_goal_list[last] = nil
	cf_list[last] = nil
	units_list[last] = nil

	list_i -= 1
	self.list_i = 0

end

-- intended to be called outside of transform replication
-- immediate transform set update
function unit.set_transform(self, position, direction)
	
	local list_i = self.list_i
	self.position = position
	self.direction = direction
	
	local cframe =
		CFrame.lookAlong(
			Vector3.new(
				position.X,
				self.y_offset,
				position.Y
			),
			Vector3.new(
				direction.X,
				0,
				direction.Y
			)
		)
	
	cf_start_list[list_i] = cframe
	cf_goal_list[list_i] = cframe
	cf_list[list_i] = cframe
	
end

-- probably could do :FindFirstDescendantOfClass
-- inside of set model but not big deal
function unit.assign_animator(self, animator)
	self.animator = animator
end

function unit.load_animation(self, name, animation_id, priority, looped)
	if not self.animator then return end
	
	-- get animation will not create a new animation
	-- if that id was already loaded
	-- and will return already made instance instead
	local animation = get_animation(animation_id)
	self.animations[name] = self.animator:LoadAnimation(animation)
	self.animations[name].Priority = priority
	self.animations[name].Looped = looped

	return self.animations[name]
end

function unit.destroy(self)
	unit.unassign_model_update(self)
	sparse_set.remove(
		set,
		self.id
	)
	self.model:Destroy()
	class.destroy(self)
end

-- transform data sent as a continious array of
-- id, position, direction
-- that way i can send all the transform data
-- through a single remote, reducing the bandwidth
-- also, cframe isnt stored inside of unit class
-- either client nor server class instance
local function transform_remote(b)

	local transform_reader = reader.new(b)

	lerp_t = time()
	
	-- position data is relative to the map size
	-- update it before decoding
	codecs.rangei.range = globals.max_distance
	codecs.rangeu.range = math.pi

	while not reader.finished(transform_reader) do

		local id = reader.read(transform_reader, codecs.u16)
		
		-- even tho there might be no unit or
		-- unit might be a local unit, i should still
		-- decode the data to move the cursor to the right position
		local pos_x = reader.read(transform_reader, codecs.rangei)
		local pos_y = reader.read(transform_reader, codecs.rangei)
		local position = Vector2.new(pos_x, pos_y)
		
		-- direction encoded as a single number
		-- later transformed into v2
		local rotation = reader.read(transform_reader, codecs.rangei)
		local direction = Vector2.new(
			math.cos(rotation),
			math.sin(rotation)
		)

		local self = sparse_set.get(set, id)
		if not self then continue end
		-- transform update of the local unit
		-- handled by a diffeent scripts
		if self.local_unit then continue end
		
		self.position = position
		self.direction = direction
		
		local list_i = self.list_i
		
		-- used for transform update later
		cf_start_list[list_i] = cf_list[list_i]
		cf_goal_list[list_i] =
			CFrame.lookAlong(
				Vector3.new(
					position.X, 
					self.y_offset,
					position.Y
				),
				Vector3.new(
					direction.X, 
					0,
					direction.Y
				)
			)

	end
end

local function damage_remote(id, health)
	local self = sparse_set.get(set, id)
	if not self then return end

	local damage = health-self.health
	self.health = health

	event.fire(self.damage_applied, damage)

end

local function walking_remote(id, walking)
	local self = sparse_set.get(set, id)
	if not self then return end

	unit.set_walking(self, walking)

end

-- cheapest transform update i could get
-- handles by a scheduler afterwards so there is no race condition
-- and functions order is deterministic
function unit.update_models()
	local t = math.min((time()-lerp_t)/(1/globals.replication_rate*1.5), 1)
	
	for i=1,list_i do
		cf_list[i] = cf_start_list[i]:Lerp(cf_goal_list[i], t)
	end
	
	-- bulkmove still is the bottleneck by a large margin
	-- probably could go further on a performance
	-- if i updated model to be a meshed skins
	-- and updated root bone C0
	workspace:BulkMoveTo(parts_list, cf_list, Enum.BulkMoveMode.FireCFrameChanged)
	
end

-- remote events connects
message.connect("units_transform", transform_remote)
message.connect("unit_damage", damage_remote)
message.connect("unit_walking", walking_remote)

return unit
