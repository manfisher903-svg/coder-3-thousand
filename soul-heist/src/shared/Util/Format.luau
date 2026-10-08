--[[
	Format
	Number and time formatting for UI and announcements.
]]

local Format = {}

local SUFFIXES = { "", "K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp", "Oc", "No", "Dc" }

function Format.Number(n: number): string
	if n ~= n or n == math.huge or n == -math.huge then
		return "∞"
	end
	local sign = n < 0 and "-" or ""
	n = math.abs(n)
	if n < 1000 then
		if n % 1 == 0 then
			return sign .. tostring(math.floor(n))
		end
		return sign .. string.format("%.1f", n)
	end
	local tier = math.min(math.floor(math.log10(n) / 3), #SUFFIXES - 1)
	local scaled = n / 10 ^ (tier * 3)
	local pattern = if scaled >= 100 then "%.0f" elseif scaled >= 10 then "%.1f" else "%.2f"
	return sign .. string.format(pattern, scaled) .. SUFFIXES[tier + 1]
end

function Format.Time(seconds: number): string
	seconds = math.max(0, math.floor(seconds))
	local h = seconds // 3600
	local m = (seconds % 3600) // 60
	local s = seconds % 60
	if h > 0 then
		return string.format("%dh %02dm", h, m)
	elseif m > 0 then
		return string.format("%dm %02ds", m, s)
	end
	return string.format("%ds", s)
end

function Format.Percent(fraction: number): string
	return string.format("%d%%", math.floor(fraction * 100 + 0.5))
end

return Format
