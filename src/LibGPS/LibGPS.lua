local lib = LibStub:NewLibrary("LibGPS", 1)

if not lib then
	return	-- already loaded and no upgrade necessary
end

function lib:SomeFunction()
-- do stuff here
end

function lib:SomeOtherFunction()
-- do other stuff here
end