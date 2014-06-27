require('luaunit')

local function getAddonName()
	local name
	for line in io.lines(".project") do
		name = line:match("^\t<name>(.+)</name>")
		if(name) then
			return name
		end
	end
	print("Could not find addon name.")
	return nil
end

local function importAddonFiles()
	for line in io.lines("src/" .. getAddonName() .. ".txt") do
		if(not line:find("^%s*##") and line:find("\.lua")) then
			require(line:match("^%s*(.+)\.lua"))
		end
	end
end

local function mockGlobals()
	function GetWindowManager()
		return {}
	end
	function GetAnimationManager()
		return {}
	end
	function GetEventManager()
		return { 
			RegisterForEvent = function() end,
			RegisterForUpdate = function() end,
		}
	end
	MAPTYPE_NONE = 0
	MAPTYPE_SUBZONE = 1
	MAPTYPE_ZONE = 2
	MAPTYPE_WORLD = 3
	MAPTYPE_ALLIANCE = 4
	MAPTYPE_COSMIC = 5

	MAP_CONTENT_NONE = 0
	MAP_CONTENT_AVA = 1
	MAP_CONTENT_DUNGEON = 2

	SET_MAP_RESULT_CURRENT_MAP_UNCHANGED = 0
	SET_MAP_RESULT_MAP_CHANGED = 1
	SET_MAP_RESULT_FAILED = 2
	
	Options_Audio_UISoundVolume = {}
	function GetSetting() return 0 end
	function SetSetting() end
end

mockGlobals()
require('esoui.libraries.globals.globalvars')
require('esoui.libraries.globals.globalapi')
require('esoui.libraries.utility.baseobject')
require('esoui.libraries.utility.zo_tableutils')
require('esoui.ingamelocalization.localizegeneratedstrings')
importAddonFiles()

require('LibGPSTest')

---- Control test output:
lu = LuaUnit
-- lu:setOutputType( "NIL" )
-- lu:setOutputType( "TAP" )
lu:setVerbosity( 1 )
os.exit( lu:run() )
