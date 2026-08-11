package.path = "data/modules/Custom Module/?.lua;" .. package.path

package.loaded.definitions = {
    LBS = 0,
    TEXT = 1
}
package.loaded.helpers = {
    roundnumber = function(value)
        return math.floor(value + 0.5)
    end
}

local voicereadback = require("voicereadback")

assert(
    voicereadback.formatFuelQuantity(12345.6789012345, "pounds")
        == "Fuel quantity 12346 pounds",
    "pound readback must be rounded to a whole unit"
)
assert(
    voicereadback.formatFuelQuantity(5432.123456789, "kilograms")
        == "Fuel quantity 5432 kilograms",
    "kilogram readback must be rounded to a whole unit"
)
assert(
    voicereadback.formatFuelQuantity(nil, "pounds") == nil,
    "invalid fuel values must not create a readback"
)

print("voice readback fuel tests passed")
