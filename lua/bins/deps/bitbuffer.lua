-- standalone version of https://github.com/Nak2/NikNaks/blob/622e3fe32246d640999260a9d8190db5c3566aa6/lua/niknaks/modules/sh_bitbuffer.lua

-- Copyright © 2022-2072, Nak, https://steamcommunity.com/id/Nak2/
-- All Rights Reserved. Not allowed to be reuploaded.
-- License: https://github.com/Nak2/NikNaks/blob/main/LICENSE

local s_char, s_byte, sub, gsub = string.char, string.byte, string.sub, string.gsub
local band, brshift, blshift, bor, bswap = bit.band, bit.rshift, bit.lshift, bit.bor, bit.bswap
local log, ldexp, frexp, floor, ceil, max, setmetatable = math.log, math.ldexp, math.frexp, math.floor, math.ceil, math.max, setmetatable

local BitBuffer = {}

local meta = {}
meta.__index = meta
function meta:__tostring()
	return "BitBuffer [" .. self:Size() .. "]"
end
-- Fixes bit-shift errors
local function rshift( int, shift )
	if shift > 31 then return 0x0 end
	return brshift( int, shift )
end

local function lshift( int, shift )
	if shift > 31 then return 0x0 end
	return blshift( int, shift )
end
-- "Crams" the data into the bitbuffer. Ignoring offsets
local function unsaferawdata( self, str )
	if #str <= 0 then return end
	local s_byte, bor, lshift = s_byte, bor, lshift
	local len = #str
	local whole = lshift(rshift(len - 4,2), 2) -- Bytes
	local p = #self._data
	for i = 1, whole, 4 do
		local a, b, c, d = s_byte( str, i, i + 3)
		p = p + 1
		self._data[ p ] = bor( lshift( a, 24 ), lshift( b, 16 ), lshift( c, 8 ), d )
	end
	self._tell = lshift( p, 5 )
	for i = whole + 1, len do
		meta.WriteByte( self, s_byte( str, i ) )
	end
	self._len = max( self._len, lshift(len, 3) )
end

local function create( data, little_endian )
	local t = {}
	t._data = {}
	t._tell = 0
	t._len = 0
	t._little_endian = false
	setmetatable(t, meta)
	if not data then return t end
	local mt = getmetatable( data )
	if type(data) == "string" then
		unsaferawdata( t, data )
		t._tell = 0 -- Reset tell
	elseif not mt then
		local q = #data
		for i = 1, q do
			t._data[i] = data[i]
		end
		t._len = q * 32
	end
	if little_endian == nil then
		t._little_endian = true
	else
		t._little_endian = little_endian
	end
	return t
end

---Creates a new BitBuffer
---@param data string|table
---@param little_endian? boolean
---@return BitBuffer
BitBuffer.Create = create
setmetatable(BitBuffer,{
	__call = function(_, data ) return create( data ) end
})

-- Simple int->string and reverse. ( Little-Endian )
do
	---Takes a string of 1-4 charectors and converts it into a Little-Endian int
	---@param str string
	---@return number
	function BitBuffer.StringToInt( str )
		local a,b,c,d = s_byte( str, 1, 4 )
		if d then
			return bor( blshift( d, 24 ), blshift( c, 16 ), blshift( b, 8 ), a )
		elseif c then
			return bor( blshift( c, 16 ), blshift( b, 8 ), a )
		elseif b then
			return bor( blshift( b, 8 ), a )
		else
			return a
		end
	end

	local q = 0xFF
	---Takes an Little-Endian number and converts it into a 4 char-string
	---@param int number
	---@return string
	function BitBuffer.IntToString( int )
		local a, b, c, d = brshift( int, 24 ), band( brshift(int, 16), q ), band( brshift(int, 8), q ), band( int, q )
		return s_char(d,c,b,a)
	end
end

-- To signed and unsigned
local to_signed, to_unsigned
do
	local maxint = {}
	local subint = {}
	for i = 1, 32 do
		local n = i
		maxint[i] = math.pow(2, n - 1)
		subint[i] = math.pow(2, n)
	end
	function to_signed( int, bits )
		if int < 0 then return int end -- Already signed
		return int - band(int, maxint[bits]) * 2
	end
	function to_unsigned( int, bits )
		return int >= 0 and int or int + subint[bits]
	end
end

-- Access
do
	---Returns lengh of the bitbuffer
	---@return number
	function meta:__len()
		return self._len
	end
	meta.Size = meta.__len

	---Returns where we're reading/writing from.
	---@return number
	function meta:Tell()
		return self._tell
	end

	---Sets the tell to a position
	---@param num number
	---@return self
	function meta:Seek( num )
		self._tell = brshift( blshift( num, 1 ), 1 )
		return self
	end

	---Skips x bits ahead.
	---@param num number
	---@return self
	function meta:Skip( num )
		self._tell = self._tell + num
		return self
	end

	---Returns true if we've reached the end of the bitbuffer.
	---@return boolean
	function meta:EndOfData()
		return self._tell >= self._len
	end

	---Clears all data from the bitbuffer
	---@return self
	function meta:Clear()
		self._data = {}
		self._len = 0
		self._tell = 0
		return self
	end

	local function toBits(num,bits,byte_space)
		local str = ""
		for i = bits, 1, -1 do
			if byte_space and i % 8 == 0 and i < 32 then
				str = str .. " "
			end
			local b = band( num, lshift( 0x1, i - 1 ) ) == 0
			str = str .. ( b and "0" or "1" )
		end
		return str
	end
	---Converts a number to bits ( Big-Endian )
	---@param num number
	---@param bits number
	---@return string
	BitBuffer.ToBits = toBits

	---Debug print function for the bitbuffer.
	function meta:Debug()
		local size = string.NiceSize( self._len / 8 )
		local rep = string.rep("=", (32 - (#size + 6)) / 2)
		print("BitBuff	" .. rep .. " [" .. size  .. "] " .. (self:IsLittleEndian() and "Le " or "Be ") .. rep .. "\t= 0xHX =")
		for i = 1, #self._data do
			print(i, toBits( self._data[i], 32 ), bit.tohex( self._data[i] ):upper())
		end
	end

	---Returns true if the bitbuffer is little-endian
	---@return boolean
	function meta:IsLittleEndian()
		return self._little_endian or false
	end

	---Returns true if the bitbuffer is big-endian
	---@param boolean
	function meta:IsBigEndian()
		return not self._little_endian
	end

	---Sets the bitbuffer to be little-endian
	---@return self
	function meta:SetLittleEndian()
		self._little_endian = true
		return self
	end

	---Sets the bitbuffer to be big-endian
	---@return self
	function meta:SetBigEndian()
		self._little_endian = false
		return self
	end
end

-- Write / Read Raw
local writeraw, readraw
do
	-- Need to check endian type here.
	-- B |--|--|FF|11|
	-- L |--|--|11|FF|

	-- B |--|-F|FF|11| -- Input
	-- S |11|FF|-F|--| -- Swap
	-- > |--|11|FF|-F| -- rshift
	-- L |--|-1|1F|FF| -- Output

	-- B |00000000|00000000|00000000|00000000|
	local b_mask = 0xFFFFFFFF
	local bswap, rshift, band, brshift = bswap, rshift, band, brshift
	local function swap( int, bits )
		return brshift( bswap( int ), 32 - bits )
	end
	function writeraw( self, int, bits )
		if self._little_endian and bits % 8 == 0 then
			int = swap( int, bits )
		end
		local rshift, bor, band, max, lshift = rshift, bor, band, max, lshift
		local tell = self._tell
		self._tell = tell + bits
		self._len = max( self._len, self._tell )
		-- Retrive data pos
		local i_word = rshift( tell, 5 ) + 1  -- [ 1 - length ]
		local bitPos = tell % 32 -- [[ 0 - 31 ]]
		local ebitPos = bitPos + bits -- The end bit pos
		-- DataMask & Data
		local mask = bor( lshift( b_mask, 32 - bitPos ), rshift( b_mask, ebitPos ) )
		local data = band( self._data[ i_word ] or 0x0, mask )
		-- Write the data
		if ebitPos <= 32 then
			self._data[ i_word ] = bor( data, lshift( int, 32 - ebitPos ) )
			return
		end
		local overflow = ebitPos - 32 -- [[ 1, 31 ]]
		self._data[ i_word ] = bor( data, rshift( int, overflow ) )
		data = band( rshift( b_mask, overflow ) , self._data[ i_word + 1 ] or 0x0)
		self._data[ i_word + 1 ] = bor( data, lshift( int, 32 - overflow ))
		return self
	end

	function readraw( self, bits )
		local rshift, band = rshift, band
		local tell = self._tell
		self._tell = tell + bits
		-- Retrive data pos
		local i_word = rshift( tell, 5 ) + 1  -- [ 1 - length ]
		local bitPos = tell % 32 -- [[ 0 - 31 ]]
		local ebitPos = bitPos + bits -- The end bit pos
		-- DataMask & Data
		if ebitPos <= 32 then
			local data = brshift( self._data[ i_word ] or 0x0, 32 - ebitPos )
			if self._little_endian and bits % 8 == 0 then
				return swap( band( data, brshift( b_mask, 32 - bits ) ), bits)
			end
			return band( data, brshift( b_mask, 32 - bits ) )
		end
		local over = ebitPos - 32 -- How many bits we're over
		local data1 = lshift( band( self._data[ i_word ] or 0x0, rshift( b_mask, bitPos ) ), over )
		local data2 = rshift( self._data[ i_word + 1 ] or 0x0, 32 - over )
		if self._little_endian and bits % 8 == 0 then
			return swap( bor( data1, data2 ), bits  )
		end
		return bor( data1, data2 )
	end
end
-- Add raw (debug) functions
meta._writeraw = writeraw
meta._readraw = readraw

-- Boolean
do
	local rshift, lshift, bor, band, max = rshift, lshift, bor, band, max
	local b_mask = 0xFFFFFFFF
	--We don't need to call write/read raw. Since this is 1 bit.

	---Writes a boolean
	---@param b boolean
	function meta:WriteBoolean( b )
		local tell = self._tell
		self._tell = tell + 1
		self._len = max( self._len, self._tell )
		-- Retrive data pos
		local i_word = rshift( tell, 5 ) + 1  -- [ 1 - length ]
		local bitPos = tell % 32 -- [[ 0 - 31 ]]
		local ebitPos = bitPos + 1
		-- DataMask & Data
		local mask = bor( lshift( b_mask, 32 - bitPos ), rshift( b_mask, ebitPos ) )
		local data = band( self._data[ i_word ] or 0x0, mask )
		-- Write the data
		self._data[ i_word ] = bor( data, lshift( b and 1 or 0, 32 - ebitPos ) )
		return self
	end

	---Reads a boolean
	---@return boolean
	function meta:ReadBoolean( )
		local tell = self._tell
		self._tell = tell + 1
		-- Retrive data pos
		local i_word = rshift( tell, 5 ) + 1  -- [ 1 - length ]
		local bitPos = tell % 32 -- [[ 0 - 31 ]]
		local ebitPos = bitPos + 1 -- The end bit pos
		-- DataMask & Data
		local data = rshift( self._data[ i_word ] or 0x0, 32 - ebitPos )
		return band( data, rshift( b_mask, 32 - 1 ) ) == 1
	end
end

-- 32 bit Int
do
	---Writes an int
	---@param int number
	---@param bits number
	meta.WriteInt = writeraw

	---Reads an int
	---@param bits number
	---@return number
	function meta:ReadInt( bits )
		return to_signed( readraw( self, bits), bits )
	end
end

-- UInt
do
	---Writes an unsigned int
	---@param int number
	---@param bits number
	meta.WriteUInt = writeraw

	local c = math.pow(2, 32)
	---Reads an unsigned int
	---@param bits number
	---@return number
	function meta:ReadUInt( bits )
		local n = readraw( self, bits )
		if n > -1 then return n end -- 32bit numbers could be negative when reading.
		return n + c
	end
end

-- Byte
do
	---Writes a byte ( 0 - 255 )
	---@param byte number
	function meta:WriteByte( byte )
		writeraw( self, byte, 8)
		return self
	end

	---Reads a byte ( 0 - 255 )
	---@return number
	function meta:ReadByte( )
		return readraw( self, 8 )
	end
end

-- Signed Byte
do
	---Writes a signed byte ( -128 - 127 )
	---@param byte number
	function meta:WriteSignedByte( byte )
		self:WriteInt( byte, 8 )
		return self
	end

	---Writes a signed byte ( -128 - 127 )
	---@return number
	function meta:ReadSignedByte( )
		return self:ReadInt( 8 )
	end
end

-- Ushort
do
	---Writes an unsigned 2 byte number ( 0 - 65535 )
	---@param num number
	function meta:WriteUShort( num )
		self:WriteUInt( num, 16 )
		return self
	end

	---Reads an unsigned 2 byte number ( 0 - 65535 )
	---@return number
	function meta:ReadUShort( )
		return self:ReadUInt( 16 )
	end
end

-- Short
do
	---Writes a 2 byte number ( -32768 - 32767 )
	---@param num number
	function meta:WriteShort( num )
		self:WriteInt( num, 16 )
		return self
	end

	---Reads an 2 byte number ( -32768 - 32767 )
	---@return number
	function meta:ReadShort( )
		return self:ReadInt( 16 )
	end
end

-- ULong
do
	---Writes an unsigned 4 byte number ( 0 - 4294967295 )
	---@param num number
	function meta:WriteULong( num )
		self:WriteUInt( num, 32 )
		return self
	end

	---Reads an unsigned 4 byte number ( 0 - 4294967295 )
	---@return number
	function meta:ReadULong( )
		return self:ReadUInt( 32 )
	end
end

-- Long
do
	---Writes a 4 byte number ( -2147483648 - 2147483647 )
	---@param num number
	function meta:WriteLong( num )
		self:WriteInt( num, 32 )
		return self
	end

	---Reads a 4 byte number ( -2147483648 - 2147483647 )
	---@return number
	function meta:ReadLong( )
		return self:ReadInt( 32 )
	end
end

-- Nibble
do
	---Writes a 4 bit unsigned number ( 0 - 15 )
	---@param num number
	function meta:WriteNibble( num )
		self:WriteUInt( num, 4 )
		return self
	end
	---Reads a 4 bit unsigned number ( 0 - 15 )
	---@return number
	function meta:ReadNibble( )
		return self:ReadUInt( 4 )
	end
end

-- Snort ( 2bit number )
do
	---Writes a 2 bit unsigned number ( 0 - 3 )
	---@param num number
	function meta:WriteSnort( num )
		self:WriteUInt( num, 2 )
		return self
	end
	---Reads a 2 bit unsigned number ( 0 - 3 )
	---@return number
	function meta:ReadSnort( )
		return self:ReadUInt( 2 )
	end
end

local function isNegative(n) return 1 / n == -math.huge end

-- Float
do
	local band = band
	---Writes an IEEE 754 little-endian float
	---@param num number
	function meta:WriteFloat( num )
		local sign = 0
		local man = 0
		local ex = 0
		-- Mark negative numbers.
		if num < 0 then
			sign = 0x80000000
			num = -num
		end
		if num ~= num then -- Nan
			ex = 0xFF
			man = 1
		elseif num == math.huge then -- Infintiy
			ex = 0xFF
			man = 0
		elseif num ~= 0 then -- Anything but 0's
			man, ex = frexp(num)
			ex = ex + 0x7F
			if ex <= 0 then
				man = ldexp( man, ex - 1 )
				ex = 0
			elseif ex >= 0xFF then -- Reached infinity
				ex = 0xFF
				man = 0
			elseif ex == 1 then
				ex = 0
			else
				man = man * 2 - 1
				ex = ex - 1
			end
			man = floor(ldexp(man, 23) + 0.5)
		elseif isNegative(num) then -- Minus 0 support
			sign = 0x80000000
			man = 0
		end
		-- Not tested, but I guess it is faster to write 1 32bit number, than 3x others.
		self:WriteULong( bor( sign, lshift(band(ex, 0xFF), 23), man ), 32 )
		return self
	end

	---Reads an IEEE 754 little-endian float
	---@return number
	local _23pow = 2 ^ 23
	function meta:ReadFloat()
		local n = self:ReadULong()
		local sign = band(0x80000000, n) == 0 and 1 or -1
		local ex = band(rshift(n, 23),0xFF)
		local man = band(n, 0x007FFFFF) / _23pow
		if ex == 0 and man == 0 then return 0 * sign				-- Number 0
		elseif ex == 255 and man == 0 then return math.huge * sign 	-- -+inf
		elseif ex == 255 and man ~= 0 then return 0 / 0				-- nan
		else return ldexp (1 + man, ex - 127) * sign end
	end
end

-- Double
do
	--[[
		|FFFFFFFF|FFFFFFFF|
		|Fa|Fb|Fc|Fd| |Fe|Ff|Fg|Fh|
		|Fh|Fg|Ff|Fe| |Fd|Fc|Fb|Fa| -> Data input

		|Fh|Fg|Ff|Fe| |Fd|Fc|Fb|Fa|
		|Fe|Ff|Fg|Fh| |Fa|Fb|Fc|Fd|
		|Fa|Fb|Fc|Fd| |Fe|Ff|Fg|Fh|
	]]
	local _52pow = 2 ^ 52
	local _32pow = 2 ^ 32
	local _log = math.log(2)
	function meta:WriteDouble( num )
		-- Calculate sign, ex and man
		local sign = 0
		if num < 0 or (num == 0 and isNegative(num)) then
			num = -num
			sign = 0x80000000
		end
		local ex	= ceil(log(num)/_log) - 1
		local man	= num / (2 ^ ex) - 1
		-- If clamp or reach math.huge
		if (ex < -1023) then
			ex = -1023
			man = num / (2 ^ ex)
		elseif (ex > 1024) then
			ex = 1024
			man = 0
		end
		if (num == 0) then -- Zero
			ex = 0
			man = 0
		elseif (num == math.huge) then --Infinity
			ex = 2047
			man = 0
		elseif (num ~= num) then  -- Nan
			ex = 2047
			man = 1
		else
			ex = ex + 1023
			man = man * _52pow
		end
		if self._little_endian then
			self:WriteULong( band( man, 0xFFFFFFFF ) )
			self:WriteULong( bor( sign, lshift(ex, 20), band( man / _32pow, 0x001FFFFF) ) )
		else
			self:WriteULong( bor( sign, lshift(ex, 20), band( man / _32pow, 0x001FFFFF) ) )
			self:WriteULong( band( man, 0xFFFFFFFF ) )
		end
		return self
	end
	function meta:ReadDouble( )
		local a, b
		if self._little_endian then
			b, a = self:ReadUInt( 32 ), self:ReadUInt( 32 )
		else
			a, b = self:ReadUInt( 32 ), self:ReadUInt( 32 )
		end
		local sign = band(0x80000000, a) == 0 and 1 or -1
		local ex = rshift( band(0x7FF00000, a), 20 )
		local man = band( a, 0x000FFFFF ) * _32pow + b
		if ex == 0 and man == 0 then return 0 * sign					-- Number 0
		elseif ex == 0x7FF and man == 0 then return math.huge * sign 	-- -+inf
		elseif ex == 0x7FF and man ~= 0 then return 0 / 0					-- nan
		else return math.pow(2, ex - 0x3FF ) * (man / _52pow + 1) * sign end
	end
end

-- Data
do
	---Writes raw string-data
	---@param str string
	function meta:Write( str )
		local lshift, bor, s_byte, WriteUInt = lshift, bor, s_byte, meta.WriteUInt
		local len = #str
		local q = lshift( rshift( len, 2 ), 2 )
		for i = 1, q, 4 do
			local a, b, c, d = s_byte( str, i, i + 3)
			WriteUInt( self, bor( lshift( a, 24 ), lshift( b, 16 ), lshift( c, 8 ), d), 32 )
		end
		for i = q + 1, len do
			WriteUInt( self, s_byte( str, i ), 8 )
		end
		return self
	end

	---Reads raw string-data. Default bytes are the length of the bitbuffer.
	---@param bytes number
	---@return string
	function meta:Read( bytes )
		bytes = bytes or math.ceil( ( self:Size() - self:Tell() ) / 8 )

		local s_char, ReadByte = s_char, meta.ReadByte
		local c, s = lshift( rshift( bytes, 2 ), 2 ), ""
		for _ = 1, c, 4 do
			s = s .. s_char( ReadByte( self ), ReadByte( self ), ReadByte( self ), ReadByte( self ) )
		end
		for _ = c + 1, bytes do
			s = s .. s_char( ReadByte( self ) )
		end
		return s
	end
end

-- Special Types
do
	local Write, Read = meta.Write, meta.Read
	---Writes a string. Max string length: 65535
	---@param str string
	function meta:WriteString( str )
		local l = #str
		if l > 65535 then
			str = sub(str, 0, 65535)
			l = 65535
		end
		self:WriteUShort( l )
		Write( self, str )
		return self
	end
	---Reads a string. Max string length: 65535
	---@return string
	function meta:ReadString( )
		return Read( self, self:ReadUShort() or 0 )
	end

	-- Writes a string using a nullbyte at the end.
	local z = '\0'
	---Writes a string using a nullbyte at the end. Note: Will remove all nullbytes given.
	---@param str string
	function meta:WriteStringNull( str )
		Write( self, gsub( str, z, '') .. z )
		return self
	end

	---Reads a string using a nullbyte at the end. Note: ReadStringNull is a bit slower than ReadString.
	---@param maxLength? number
	---@return string
	function meta:ReadStringNull( maxLength )
		maxLength = maxLength or ceil( self:Size() - self:Tell() ) / 8
		local str = ""
		if maxLength < 1 then return str end
		local c = self:ReadByte()
		while c ~= 0 and maxLength > 0 do
			str = str .. s_char( c )
			c = self:ReadByte()
			maxLength = maxLength - 1
		end
		return str
	end

	---Writes a vector
	---@param vector Vector
	function meta:WriteVector( vector )
		self:WriteFloat( vector.x )
		self:WriteFloat( vector.y )
		self:WriteFloat( vector.z )
		return self
	end

	---Reads a vector
	---@return Vector
	function meta:ReadVector()
		return Vector(self:ReadFloat(), self:ReadFloat(), self:ReadFloat())
	end

	---Writes an angle
	---@param angle Angle
	function meta:WriteAngle( angle )
		self:WriteFloat( angle.p )
		self:WriteFloat( angle.y )
		self:WriteFloat( angle.r )
		return self
	end

	---Reads an angle
	---@return Angle
	function meta:ReadAngle()
		return Angle(self:ReadFloat(), self:ReadFloat(), self:ReadFloat())
	end

	---Writes a 32bit color
	---@param color Color
	function meta:WriteColor( color )
		self:WriteByte( color.r )
		self:WriteByte( color.g )
		self:WriteByte( color.b )
		self:WriteByte( color.a or 255 )
		return self
	end

	---Reads a 32bit color
	---@return Color
	function meta:ReadColor( )
		return Color( self:ReadByte( ), self:ReadByte( ), self:ReadByte( ), self:ReadByte( ) )
	end
end

-- Tables / Types
do
	local tab = {
		["nil"] 	= 0,
		["boolean"]	= 1,
		["number"]	= 2,
		-- light userdata
		["string"]	= 4,
		["table"]	= 5,
		-- function
		-- userdata
		-- thread
		["Player"]	= 8,
		["Entity"]	= 9,
		["Vector"]	= 10,
		["Angle"]	= 11,
		-- physobj
		["IMaterial"]	= 21,
		["Color"]		= 255
	}
	---Writes a type using a byte as TYPE_ID.
	---@param obj any
	function meta:WriteType( obj )
		local id = tab[ type( obj )]
		assert(id, "Trying to write invalid type [" .. type( obj ) .. "]")
		if id == 5 and obj.r and obj.g and obj.b then
			id = 255
		end
		self:WriteByte( id )
		if id == 0 then return
		elseif id == 1 then self:WriteByte( obj and 1 or 0 )
		elseif id == 2 then self:WriteDouble( obj )
		elseif id == 4 then self:WriteString( obj)
		elseif id == 5 then	self:WriteTable( obj )
		elseif id == 8 then self:WriteString( obj:SteamID64() )
		elseif id == 9 then self:WriteULong( obj:EntIndex() )
		elseif id == 10 then self:WriteVector( obj )
		elseif id == 11 then self:WriteAngle( obj )
		elseif id == 21 then self:WriteString( obj:GetName() )
		elseif id == 255 then self:WriteColor( obj )
		end
		return self
	end

	---Reads a type using a byte as TYPE_ID.
	---@return any
	function meta:ReadType()
		local id = self:ReadByte()
		if id == 0 then return
		elseif id == 1 then return self:ReadByte( ) == 1
		elseif id == 2 then return self:ReadDouble( )
		elseif id == 4 then return self:ReadString( )
		elseif id == 5 then	return self:ReadTable( )
		elseif id == 8 then
			id = self:ReadString()
			local plys = player.GetAll()
			for i = 1, #plys do
				if plys[i]:SteamID64() == id then
					return plys[i]
				end
			end
		elseif id == 9 then 	return Entity( self:ReadULong( ) )
		elseif id == 10 then 	return self:ReadVector( )
		elseif id == 11 then 	return self:ReadAngle( )
		elseif id == 21 then 	return Material( self:ReadString( ) )
		elseif id == 255 then 	return self:ReadColor( )
		end
	end

	---Writes a table
	---@param tbl table
	function meta:WriteTable( tbl )
		-- Table
		for k, v in pairs( tbl ) do
			self:WriteType( k )
			self:WriteType( v )
		end
		self:WriteByte( 0 )
		return self
	end

	---Reads a table. Default maxValues is 150
	---@param maxValues? number
	---@return table
	function meta:ReadTable( maxValues )
		maxValues = maxValues or 150
		-- Table
		local tbl = {}
		local k = self:ReadType()
		while k ~= nil and maxValues > 0 do
			tbl[k] = self:ReadType()
			k = self:ReadType()
			maxValues = maxValues - 1
		end
		return tbl
	end
end

-- File functions
do
	---Same as file.Open, but returns it as a bitbuffer. little_endian is true by default.
	---@param fileName string
	---@param gamePath? string
	---@param lzma? boolean
	---@param little_endian? boolean
	---@return BitBuffer
	function BitBuffer.OpenFile( fileName, gamePath, lzma, little_endian )
		if ( gamePath == true ) then gamePath = "GAME" end
		if ( gamePath == nil or gamePath == false ) then gamePath = "DATA" end
		local f = file.Open( fileName, "rb", gamePath )
		if not f then return end
		-- Data
		local str = f:Read( f:Size() ) -- Is faster
		if lzma then
			str = util.Decompress( str ) or str
		end
		f:Close()
		local b = BitBuffer(str, little_endian)
		b:Seek(0)
		return b
	end

	---Saves the bitbuffer to a file within the data folder. Returns true if it got saved.
	---@param fileName string
	---@param lzma? boolean
	---@return boolean
	function meta:SaveToFile( fileName, lzma )
		local f = file.Open( fileName, "wb", "DATA" )
		if not f then return false end
		local s = self:Size()
		local t = self:Tell()
		if not lzma then
			local n = rshift(s, 5) -- Amount of "chunks"
			for i = 1, n do
				f:WriteULong( self._data[i] )
			end
			local p = lshift( n, 5 )
			self:Seek( p )
			local l = s - p -- How many bits left to write.
			for _ = 1, math.ceil( l / 8 ) do
				f:WriteByte( f:ReadByte() )
			end
		else
			self:Seek( 0 )
			local data = self:Read()
			data = util.Compress( data ) or data
			f:Write(data)
		end
		self:Seek( t )
		f:Close()
		return true
	end
end

-- Net functions
function meta:ReadFromNet( bits )
	for _ = 1, bits / 32 do
		self:WriteUInt( net.ReadUInt( 32 ), 32)
	end
	local leftover = bits % 32
	if leftover > 0 then
		self:WriteUInt( net.ReadUInt( leftover ), leftover)
	end
	self:Seek(0)
	return self
end
function BitBuffer.FromNet( bits )
	return BitBuffer():ReadFromNet( bits )
end
function meta:WriteToNet()
	local tell = self:Tell()
	self:Seek(0)
	local l = self:Size()
	for _ = 1, l / 32 do
		net.WriteUInt( self:ReadULong(), 32)
	end
	local leftover = l % 32
	if leftover > 0 then
		net.WriteUInt( self:ReadUInt(leftover), leftover)
	end
	self:Seek(tell)
	return l
end
function BitBuffer.ToNet( buf )
	return buf:WriteToNet()
end

return BitBuffer