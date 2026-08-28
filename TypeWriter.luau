--[[
	TypeWriter script for a custom rendering of text used for a dialogue system
	created by @ivaniko_. on discord
]]

-- abstracted per character logic into its own module
-- mainly used for effects such as "shaking" or "fading"
local Letter = require(script:WaitForChild("Letter"))

local TypeWriter = {}
TypeWriter.__index = TypeWriter

-- better using these than textservice implementation
-- the latter gives undesirable results
local pSize = 0.3
local lSize = 0.5

-- lua string pattern
local lengthPattern = "[%p ]"

-- markup tag
local formatpattern = "<.->"

function TypeWriter.new(frame : GuiBase2d)
	local self = setmetatable({}, TypeWriter)

	self.Frame = frame
	
	-- can be modified
	self.Text = ""
	self.Font = Enum.Font.SourceSansBold
	self.TextSize = 14
	self.LetterSpeed = 40
	self.PunctuationSpeed = 3
	self.FadeSpeed = 4
	self.FadeSizeAdditive = 5
	self.FadePositionAdditive = UDim2.new(0,4,0,4)
	
	-- needed for new line check
	self.FrameSize = frame.AbsoluteSize.X

	self.xPos = 0
	self.yPos = 0
	self.line = 0

	-- every "Letter" instance
	self.chars = {}

	self.ClickConnect = nil
	self.SkipDialog = false

	-- coroutine1 handles spawning characters
	-- coroutine2 handles delay between spawning characters
	self.Coroutine1 = nil
	self.Coroutine2 = nil

	-- Markups = table of markup key/value pairs ({color = "red"})
	--           while scanning through self.Text in FormatText.
	-- Subtext = the text broken into tables, 
	--           where each table is {text, markup}
	-- Words   = subtext further broken down into individual words/spaces
	--			 TypeWriter handles text in a chunks of words to exclude the hyphenation
	self.Markups = {}
	self.Subtext = {}
	self.Words = {}

	return self
end

-- manually set skip button in the ui
-- since interface can change
function TypeWriter:SetSkipButton(button : GuiButton)
	if self.ClickConnect then
		self.ClickConnect:Disconnect()
	end
	self.ClickConnect = button.Activated:Connect(function()
		if self.Coroutine1 then
			self.SkipDialog = true
			coroutine.resume(self.Coroutine1)
		end
	end)
end

-- resets the typewritter to a blank state
function TypeWriter:Clear()
	
	if self.Coroutine1 then
		coroutine.close(self.Coroutine1)
		coroutine.close(self.Coroutine2)
		self.Coroutine1 = nil
		self.Coroutine2 = nil
	end

	self.SkipDialog = false

	self.xPos = 0
	self.yPos = 0
	self.line = 0

	self.Markups = {}
	self.Subtext = {}
	self.Words = {}

	-- dont forget the characters/letters
	for _, char in self.chars do
		char:Destroy()
	end
	table.clear(self.chars)
end

-- returns the width of a string
-- punctuation uses different character size
function TypeWriter:GetLength(str : string)
	local toReturn = 0

	-- multi bytes characters support using utf8
	for i,v in utf8.codes(str) do
		local char = utf8.char(v)
		if string.match(char, lengthPattern) then
			toReturn += self.TextSize * pSize
		else
			toReturn += self.TextSize * lSize
		end
	end

	return toReturn
end

-- spawns a character and applies markdown
function TypeWriter:PlaceCharacter(char : string, markup : {})

	local length = self:GetLength(char)

	local appearPosition = UDim2.new(0,self.xPos,0,self.yPos)
	local fadePosition = appearPosition + self.FadePositionAdditive

	local appearSize = self.TextSize
	local fadeSize = appearSize + self.FadeSizeAdditive

	local char = Letter.new(char, self.Frame, fadePosition)
	char.AppearPosition = appearPosition
	char.FadePosition = fadePosition
	char.AppearSize = appearSize
	char.FadeSize = fadeSize

	char.TextLabel.Font = self.Font
	char.TextLabel.Position = fadePosition
	char.TextLabel.TextSize = fadeSize
	char.TextLabel.TextColor3 = Color3.fromRGB(90,90,90)

	-- custom character effects handled outside of this script
	char:Markup(markup)
	char:Appear(1/self.FadeSpeed)

	-- offset the cursor
	self.xPos += length

	table.insert(self.chars, char)

end

-- iterates through words and spawns all characters
-- coroutines behaviour described in TypeWriter.new()
function TypeWriter:PlaceText()
	
	local punctuation = false
	local updateText = true

	self.Coroutine1 = coroutine.create(function()
		for _,word in self.Words do

			local str = word[1]
			local markup = word[2]

			-- new line check
			if self.xPos + self:GetLength(str) > self.FrameSize then
				self.line += 1
				self.yPos = self.line * self.TextSize
				self.xPos = 0
			end

			for i, v in utf8.codes(str) do

				local char = utf8.char(v)
				self:PlaceCharacter(char, markup)

				-- player input handilng
				if not self.SkipDialog then
					punctuation = string.match(char, "%p")
					coroutine.yield()
				end

			end

		end

		-- tell coroutine2 to stop
		updateText = false
	end)
	self.Coroutine2 = coroutine.create(function()
		while updateText do
			-- wait longer after punctuation
			if punctuation then
				task.wait(1/self.PunctuationSpeed)
			else
				task.wait(1/self.LetterSpeed)
			end
			coroutine.resume(self.Coroutine1)
		end
	end)

	-- placing first character immediately
	coroutine.resume(self.Coroutine1)
	coroutine.resume(self.Coroutine2)

end

-- splits text into words
function TypeWriter:SplitText()
	for _,sub in self.Subtext do

		local text = sub[1]
		local marks = sub[2]

		local word = ""

		for i, v in utf8.codes(text) do

			local char = utf8.char(v)
			
			-- new word check
			if char == " " then
				if word ~= "" then
					table.insert(self.Words, {word, marks})
					word = ""
				end
				table.insert(self.Words , {" ", marks})
			else
				word = word..char
			end

		end

		-- adding any left ups to the words table
		if word ~= "" then
			table.insert(self.Words, {word, marks})
		end

	end
end

-- separates the text from markup tags
function TypeWriter:FormatText()

	-- using string patters to find markup tags
	for markup in self.Text:gmatch(formatpattern) do

		-- gmatch finds the match, but not position
		local i,j = self.Text:find(markup)
		local formattedText = self.Text:sub(1,i-1)

		-- adding every markup tag applied to the text
		table.insert(self.Subtext, {formattedText, table.clone(self.Markups)})

		-- parse "<name=value>" into its two parts and update the active markup state
		-- a value of the literal string "nil" clears that markup key (closing tag)
		local name, value = markup:match("<(.+)=(.+)>")
		if value == "nil" then
			self.Markups[name] = nil
		else
			self.Markups[name] = value
		end

		-- remove the text we already scanned
		-- continue scanning whats left
		self.Text = self.Text:sub(j+1, #self.Text)

	end

	-- whatever text remains after the last tag (or the whole text, if there were no
	-- tags at all) is one final run under whatever markup state is left active
	table.insert(self.Subtext, {self.Text, self.Markups})

end

-- replace the currently disaplyed text with a new one
-- pipeline:
--   1. Clear()       - resets the TypeWriter
--   2. FormatText()  - separates text from markdown tags
--   3. SplitText()   - splits the text into words
--   4. PlaceText()   - self explanatory
function TypeWriter:ChangeText(newText : string)

	self.Text = newText

	self:Clear()

	self:FormatText()
	self:SplitText()
	self:PlaceText()
	
end

return TypeWriter
