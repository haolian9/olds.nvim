---@class olds.G
---@field create_client fun(): olds.Client

---@type olds.G
local g = require("infra.G")("olds")

return g
