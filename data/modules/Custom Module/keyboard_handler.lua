local handler
local b_handler = false

function register_handler(hdl)
	if b_handler and hdl ~= nil then
		sasl.logDebug(hdl)
		sasl.logDebug("this handler is already set... nothing to do")
		return false
	else
		handler = hdl
		sasl.logDebug(hdl)
		if hdl ~= nil then
			b_handler = true
			sasl.logDebug("Registering this handler")
			else
			b_handler = false
			sasl.logDebug("UN-registering this handler")
			end		
		return true
	end	
end

local function key_handler(char, vkey, shift, ctrl, alt, event)
	if b_handler then
		local release = handler(char, vkey, shift, ctrl, alt, event)
		if release then
			sasl.logDebug("Key press and releasing handler")
			b_handler = false
		end
		return true
	end
	return false
end

registerGlobalKeyHandler(key_handler)
