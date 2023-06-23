local BitBuffer = include("deps/bitbuffer.lua")

_G.bins = {}

function bins.encode(tbl)
	local buff = BitBuffer()
	buff:WriteTable(tbl)
	buff:Seek(0)
	return buff:Read()
end

function bins.decode(raw)
	local buff = BitBuffer()
	buff:Write(raw)
	buff:Seek(0)
	return buff:ReadTable()
end