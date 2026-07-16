local M = {}

local UINT32 = 4294967296
local UINT32_MASK = UINT32 - 1

local function normalize32(value)
    value = value % UINT32
    if value < 0 then value = value + UINT32 end
    return value
end

local bitlib = rawget(_G, "bit") or rawget(_G, "bit32")
if not bitlib then
    local ok, loaded = pcall(require, "bit")
    if ok then bitlib = loaded end
end

local band2
local bxor2
local bnot32
local rshift32
local ror32

if bitlib and bitlib.band and bitlib.bxor and bitlib.bnot and bitlib.rshift then
    band2 = function(a, b) return normalize32(bitlib.band(a, b)) end
    bxor2 = function(a, b) return normalize32(bitlib.bxor(a, b)) end
    bnot32 = function(a) return normalize32(bitlib.bnot(a)) end
    rshift32 = function(a, count) return normalize32(bitlib.rshift(a, count)) end
    local rotate = bitlib.ror or bitlib.rrotate
    if rotate then
        ror32 = function(a, count) return normalize32(rotate(a, count)) end
    end
else
    local function bit_pair(a, b, exclusive)
        a = normalize32(a)
        b = normalize32(b)
        local result = 0
        local place = 1
        for _ = 1, 32 do
            local abit = a % 2
            local bbit = b % 2
            local set = exclusive and abit ~= bbit or (not exclusive and abit == 1 and bbit == 1)
            if set then result = result + place end
            a = (a - abit) / 2
            b = (b - bbit) / 2
            place = place * 2
        end
        return result
    end

    band2 = function(a, b) return bit_pair(a, b, false) end
    bxor2 = function(a, b) return bit_pair(a, b, true) end
    bnot32 = function(a) return UINT32_MASK - normalize32(a) end
    rshift32 = function(a, count)
        return math.floor(normalize32(a) / (2 ^ count))
    end
end

if not ror32 then
    ror32 = function(a, count)
        a = normalize32(a)
        local low = a % (2 ^ count)
        return normalize32(rshift32(a, count) + low * (2 ^ (32 - count)))
    end
end

local function bxor3(a, b, c)
    return bxor2(bxor2(a, b), c)
end

local function add32(...)
    local result = 0
    for index = 1, select("#", ...) do
        result = result + (select(index, ...) or 0)
    end
    return normalize32(result)
end

local K = {
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5,
    0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
    0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3,
    0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
    0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc,
    0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7,
    0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
    0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13,
    0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
    0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3,
    0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5,
    0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
    0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208,
    0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
}

local function word_bytes(value)
    value = normalize32(value)
    return string.char(
        math.floor(value / 16777216) % 256,
        math.floor(value / 65536) % 256,
        math.floor(value / 256) % 256,
        value % 256
    )
end

local HEX = "0123456789abcdef"
local function word_hex(value)
    value = normalize32(value)
    local out = {}
    for shift = 28, 0, -4 do
        local digit = math.floor(value / (2 ^ shift)) % 16
        out[#out + 1] = HEX:sub(digit + 1, digit + 1)
    end
    return table.concat(out)
end

function M.hex(data)
    data = tostring(data or "")
    local byteLength = #data
    local bitHigh = math.floor(byteLength / 536870912)
    local bitLow = (byteLength * 8) % UINT32
    local padLength = (56 - ((byteLength + 1) % 64)) % 64
    local message = data .. string.char(0x80) .. string.rep("\0", padLength)
        .. word_bytes(bitHigh) .. word_bytes(bitLow)

    local h0, h1, h2, h3 = 0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a
    local h4, h5, h6, h7 = 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19
    local words = {}

    for offset = 1, #message, 64 do
        for index = 1, 16 do
            local base = offset + (index - 1) * 4
            local b1, b2, b3, b4 = message:byte(base, base + 3)
            words[index] = b1 * 16777216 + b2 * 65536 + b3 * 256 + b4
        end
        for index = 17, 64 do
            local x = words[index - 15]
            local y = words[index - 2]
            local s0 = bxor3(ror32(x, 7), ror32(x, 18), rshift32(x, 3))
            local s1 = bxor3(ror32(y, 17), ror32(y, 19), rshift32(y, 10))
            words[index] = add32(words[index - 16], s0, words[index - 7], s1)
        end

        local a, b, c, d = h0, h1, h2, h3
        local e, f, g, h = h4, h5, h6, h7
        for index = 1, 64 do
            local sigma1 = bxor3(ror32(e, 6), ror32(e, 11), ror32(e, 25))
            local choose = bxor2(band2(e, f), band2(bnot32(e), g))
            local temp1 = add32(h, sigma1, choose, K[index], words[index])
            local sigma0 = bxor3(ror32(a, 2), ror32(a, 13), ror32(a, 22))
            local majority = bxor3(band2(a, b), band2(a, c), band2(b, c))
            local temp2 = add32(sigma0, majority)
            h = g
            g = f
            f = e
            e = add32(d, temp1)
            d = c
            c = b
            b = a
            a = add32(temp1, temp2)
        end

        h0 = add32(h0, a)
        h1 = add32(h1, b)
        h2 = add32(h2, c)
        h3 = add32(h3, d)
        h4 = add32(h4, e)
        h5 = add32(h5, f)
        h6 = add32(h6, g)
        h7 = add32(h7, h)
    end

    return word_hex(h0) .. word_hex(h1) .. word_hex(h2) .. word_hex(h3)
        .. word_hex(h4) .. word_hex(h5) .. word_hex(h6) .. word_hex(h7)
end

return M
