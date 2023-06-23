FindMetaTable("Color").MetaName = "Color" -- fix color meta name

local function GetType(v)
	return getmetatable(v) and getmetatable(v).MetaName or type(v)
end

local function debug(tbl, lvl)
	lvl = lvl or 0
	local indent = string.rep("    ", lvl)

	local later = {}

	for k, v in pairs(tbl) do
		if (istable(v) and (getmetatable(v) and getmetatable(v).__tostring) == nil) == false then
			print(string.format(
				"%s`%s` %s = `%s` %s",
				indent,
				GetType(k), k,
				GetType(v), v
			))
		else
			later[#later + 1] = {k, v}
		end
	end

	for _, v in ipairs(later) do
		print(string.format(
			"%s`%s` %s = {",
			indent,
			GetType(v[1]), v[1]
		))

		debug(v[2], lvl + 1)

		print(string.format("%s}", indent))
	end
end

local raw = {
	[1] = "one",
	hello = "World",
	gmod_classes = {
		col = Color(255, 0, 0),
		vec = Vector(1, 2, 3),
		ang = Angle(3, 2, 1)
	}
}

local encoded = bins.encode(raw)
local decoded = bins.decode(encoded)

print(string.rep("  \n", 10))
debug(decoded)

file.CreateDir("bins")
file.Write("bins/bins.dat", encoded)
file.Write("bins/json.json", util.TableToJSON(raw))