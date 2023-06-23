# BinS
BINary Serialization format - based on niknaks bitbuffers


usage:
```lua
	local encoded_binary = bins.encode(tbl)
	local decoded_table = bins.decode(encoded_binary)
```

it doesnt have known gmod json issues
for example:
gmod json decoder fuckup string keys, `util.JSONToTable('{"76561198086005321": "Beelzebub"}')` will return `{[7.6561198086005e+16] = "Beelzebub"}`
gmod json doesnt support color class
e.t.c

credits: https://github.com/Nak2/NikNaks