--executes lua 5.1 bytecode--
local bit = bit32 or require "bit"
if not bit.blshift then
	bit.blshift = bit.lshift
	bit.brshift = bit.rshift
end

local unpack = unpack or table.unpack

vm = {}
vm.debug = false
vm.typechecking = true

local debug = vm.debug and print or function() end

local instructionNames = {
	[0]="MOVE","LOADK","LOADBOOL","LOADNIL",
	"GETUPVAL","GETGLOBAL","GETTABLE",
	"SETGLOBAL","SETUPVAL","SETTABLE","NEWTABLE",
	"SELF","ADD","SUB","MUL","DIV","MOD","POW","UNM","NOT","LEN","CONCAT",
	"JMP","EQ","LT","LE","TEST","TESTSET","CALL","TAILCALL","RETURN",
	"FORLOOP","FORPREP","TFORLOOP","SETLIST","CLOSE","CLOSURE","VARARG"
}

local ins = {}
for i, v in pairs(instructionNames) do ins[v] = i end

local iABC = 0
local iABx = 1
local iAsBx = 2

local instructionFormats = {
	[0]=iABC,iABx,iABC,iABC,
	iABC,iABx,iABC,
	iABx,iABC,iABC,iABC,
	iABC,iABC,iABC,iABC,iABC,iABC,iABC,iABC,iABC,iABC,iABC,
	iAsBx,iABC,iABC,iABC,iABC,iABC,iABC,iABC,iABC,
	iAsBx,iAsBx,iABC,iABC,iABC,iABx,iABC
}

local band, brshift = bit.band, bit.brshift
local tostring, unpack = tostring, unpack

local vm_globals = setmetatable({},{__mode="k"})

function vm.run(chunk, args, upvals, globals, hook, yourself)
	local R = {}
	local top = 0
	local pc = 0
	local code = chunk.instructions
	local constants = chunk.constants
	args = args or {}
	upvals = upvals or {}
	globals = globals or _G
	yourself = yourself or "main"
	if vm_globals[yourself] == nil then
		vm_globals[yourself] = globals
	end
	local openUpvalues = {}
	for i=1,chunk.nparam do R[i-1] = args[i] top = i-1 end
	
	local function decodeInstruction(inst)
		local opcode = band(inst,0x3F)
		local format = instructionFormats[opcode]
		if format == iABC then
			return opcode, band(brshift(inst,6),0xFF), band(brshift(inst,23),0x1FF), band(brshift(inst,14),0x1FF)
		elseif format == iABx then
			return opcode, band(brshift(inst,6),0xFF), band(brshift(inst,14),0x3FFFF)
		elseif format == iAsBx then
			local sBx = band(brshift(inst,14),0x3FFFF)-131071
			return opcode, band(brshift(inst,6),0xFF), sBx
		else
			error(opcode.." "..format)
		end
	end
	
	local function getsBx(inst)
		local sBx = band(brshift(inst,14),0x3FFFF)-131071
		return sBx
	end
	
	local function RK(n)
		return n >= 256 and constants[n-256] or R[n]
	end
	
	local typecheck
	if vm.typechecking then
		function typecheck(v,...)
			local t = type(v)
			for i=1, select("#",...) do
				if t == select(i,...) then return end
			end
			error((...).." expected, got "..t)
		end
	else
		function typecheck() end
	end
	
	--instruction constants--
	local MOVE = 0
	local LOADK = 1
	local LOADBOOL = 2
	local LOADNIL = 3
	local GETUPVAL = 4
	local GETGLOBAL = 5
	local GETTABLE = 6
	local SETGLOBAL = 7
	local SETUPVAL = 8
	local SETTABLE = 9
	local NEWTABLE = 10
	local SELF = 11
	local ADD = 12
	local SUB = 13
	local MUL = 14
	local DIV = 15
	local MOD = 16
	local POW = 17
	local UNM = 18
	local NOT = 19
	local LEN = 20
	local CONCAT = 21
	local JMP = 22
	local EQ = 23
	local LT = 24
	local LE = 25
	local TEST = 26
	local TESTSET = 27
	local CALL = 28
	local TAILCALL = 29
	local RETURN = 30
	local FORLOOP = 31
	local FORPREP = 32
	local TFORLOOP = 33
	local SETLIST = 34
	local CLOSE = 35
	local CLOSURE = 36
	local VARARG = 37
	
	--local ret = {pcall(function()
		while true do
			local o,a,b,c = decodeInstruction(code[pc])
			if vm.debug then debug(pc,instructionNames[o],a,b,c) end
			pc = pc+1
			if hook then hook() end
		
			if o == MOVE then
				R[a] = R[b]
			elseif o == LOADNIL then
				for i=a, c do
					R[i] = nil
				end
			elseif o == LOADK then
				R[a] = constants[b]
			elseif o == ins.LOADBOOL then
				R[a] = b ~= 0
				if c ~= 0 then
					pc = pc+1
				end
			elseif o == GETGLOBAL then
				R[a] = vm_globals[yourself][constants[b]]
			elseif o == SETGLOBAL then
				vm_globals[yourself][constants[b]] = R[a]
			elseif o == GETUPVAL then
				R[a] = upvals[b]
			elseif o == SETUPVAL then
				upvals[b] = R[a]
			elseif o == GETTABLE then
				R[a] = R[b][RK(c)]
			elseif o == SETTABLE then
				R[a][RK(b)] = RK(c)
			elseif o == ADD then
				R[a] = RK(b)+RK(c)
			elseif o == SUB then
				R[a] = RK(b)-RK(c)
			elseif o == MUL then
				R[a] = RK(b)*RK(c)
			elseif o == DIV then
				R[a] = RK(b)/RK(c)
			elseif o == MOD then
				R[a] = RK(b)%RK(c)
			elseif o == POW then
				R[a] = RK(b)^RK(c)
			elseif o == UNM then
				R[a] = -RK(c)
			elseif o == NOT then
				R[a] = not RK(c)
			elseif o == LEN then
				R[a] = #RK(c)
			elseif o == CONCAT then
				local sct = {}
				for i=b, c do sct[#sct+1] = tostring(R[i]) end
				R[a] = table.concat(sct)
			elseif o == JMP then
				pc = (pc+b)
			elseif o == CALL then
				typecheck(R[a],"function")
				local ret
				if b == 1 then
					if c == 1 then
						R[a]()
					elseif c == 2 then
						R[a] = R[a]()
					else
						ret = {R[a]()}
					
						if c == 0 then
							for i=a, a+#ret-1 do R[i] = ret[i-a+1] top = i end
						else
							local g = 1
							for i=a, a+c-2 do R[i] = ret[g] g=g+1 end
						end
					end
				else
					--local cargs = {}
					local s,e
					if b == 0 then
						s,e=a+1,top
						--for i=a+2, chunk.maxStack-2 do cargs[#cargs+1] = R[i] end
					else
						s,e=a+1,a+b-1
						--for i=a+1, a+b-1 do cargs[#cargs+1] = R[i] end
					end
					if c == 1 then
						R[a](unpack(R,s,e))
					elseif c == 2 then
						R[a] = R[a](unpack(R,s,e))
					else
						ret = {R[a](unpack(R,s,e))}
				
						if c == 0 then
							for i=a, a+#ret-1 do R[i] = ret[i-a+1] top = i end
						else
							local g = 1
							for i=a, a+c-2 do R[i] = ret[g] g=g+1 end
						end
					end
				end
			elseif o == RETURN then
				local ret = {}
				for i=a, a+b-2 do ret[#ret+1] = R[i] end
				return unpack(ret)
			elseif o == TAILCALL then
				local cargs = {}
				if b == 0 then
					for i=a+2, top do cargs[#cargs+1] = R[i] end
				else
					for i=a+1, a+b-1 do cargs[#cargs+1] = R[i] end
				end
				return R[a](unpack(cargs))
			elseif o == VARARG then
				if b > 0 then
					local i = 1
					for n=a, a+b-1 do
						R[n] = args[i]
						i = i+1
					end
				else
					for i=chunk.nparam+1, #args do
						R[a+i-1] = args[i]
						top = a+i-1
					end
				end
			elseif o == SELF then
				R[a+1] = R[b]
				R[a] = R[b][RK(c)]
			elseif o == EQ then
				if (RK(b) == RK(c)) == (a ~= 0) then
					pc = pc+getsBx(code[pc])+1
				else
					pc = pc+1
				end
			elseif o == LT then
				if (RK(b) < RK(c)) == (a ~= 0) then
					pc = pc+getsBx(code[pc])+1
				else
					pc = pc+1
				end
			elseif o == LE then
				if (RK(b) <= RK(c)) == (a ~= 0) then
					pc = pc+getsBx(code[pc])+1
				else
					pc = pc+1
				end
			elseif o == TEST then
				if (not R[a]) ~= (c ~= 0) then
					pc = pc+getsBx(code[pc])+1
				else
					pc = pc+1
				end
			elseif o == TESTSET then
				if (not R[b]) ~= (c ~= 0) then
					R[a] = R[b]
					pc = pc+1
				else
					pc = pc+getsBx(code[pc])+1
				end
			elseif o == FORPREP then
				R[a] = R[a]-R[a+2]
				pc = pc+b
			elseif o == FORLOOP then
				local step = R[a+2]
				R[a] = R[a]+step
				local idx = R[a]
				local limit = R[a+1]
			
				if (step < 0 and limit <= idx or idx <= limit) then
					pc = pc+b
					R[a+3] = R[a]
				end
			elseif o == TFORLOOP then
				local ret = {R[a](R[a+1],R[a+2])}
				local i = 1
				for n=a+3, a+3+b do R[n] = ret[i] i=i+1 end
				if R[a+3] ~= nil then
					R[a+2] = R[a+3]
				else
					pc = pc+1
				end
			elseif o == NEWTABLE then
				R[a] = {}
			elseif o == SETLIST then
				for i=1, b do
					R[a][((c-1)*50)+i] = R[a+i]
				end
			elseif o == CLOSURE then
				local proto = chunk.functionPrototypes[b]
				local upvaldef = {}
				local upvalues = setmetatable({},{__index=function(_,i)
					if not upvaldef[i] then error("unknown upvalue") end
					local uvd = upvaldef[i]
					if uvd.type == 0 then --local upvalue
						return R[uvd.reg]
					elseif uvd.type == 1 then
						return upvals[uvd.reg]
					else
						return uvd.storage
					end
				end,__newindex=function(_,i,v)
					if not upvaldef[i] then error("unknown upvalue") end
					local uvd = upvaldef[i]
					if uvd.type == 0 then --local upvalue
						R[uvd.reg] = v
					elseif uvd.type == 1 then
						upvals[uvd.reg] = v
					else
						uvd.storage = v
					end
				end})
				local myself
				myself = function(...)
					return vm.run(proto, {...}, upvalues, vm_globals[myself], hook, myself)
				end
				vm_globals[myself] = vm_globals[yourself]
				R[a] = myself
				for i=1, proto.nupval do
					local o,a,b,c = decodeInstruction(code[pc+i-1])
					debug(pc+i,"PSD",instructionNames[o],a,b,c)
					if o == MOVE then
						upvaldef[i-1] = openUpvalues[b] or {type=0,reg=b}
						openUpvalues[b] = upvaldef[i-1]
					elseif o == GETUPVAL then
						upvaldef[i-1] = {type=1,reg=b}
					else
						error("unknown upvalue psuedop")
					end
				end
				pc = pc+proto.nupval
			elseif o == CLOSE then
				for i=a, chunk.maxStack do
					if openUpvalues[i] then
						local ouv = openUpvalues[i]
						ouv.type = 2 --closed
						ouv.storage = R[ouv.reg]
						openUpvalues[i] = nil
					end
				end
			else
				error("Unknown opcode!")
			end
		end
	--[[end)}
	if not ret[1] then
		error(ret[2].." at pc "..(pc-1).." line "..chunk.sourceLines[pc-1])
	else
		return unpack(ret,2)
	end]]
end

vm.lib = {}
function vm.lib.setfenv(thing, env)
	checkArg(2,env,"table")
	checkArg(1,thing,"function","number")
	if type(thing) == "number" then
		error("bad argument #1 to 'setfenv' (invalid level)",2)
	elseif vm_globals[thing] == nil then
		error("'setfenv' cannot change environment of given object",2)
	end
	vm_globals[thing] = env
	return thing
end
function vm.lib.getfenv(thing)
	checkArg(1,thing,"function","number","nil")
	if type(thing) == "number" then
		error("bad argument #1 to 'getfenv' (invalid level)",2)
	elseif type(thing) == "function" then
		return vm_globals[thing] or vm_globals["main"]
	else
		return vm_globals["main"]
	end
end
