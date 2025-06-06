local ffi = require "ffi"


local bor = bit.bor
local type = type
local pairs = pairs
local rawget = rawget
local tbl_concat = table.concat
local setmetatable = setmetatable
local ffi_string = ffi.string
local ffi_gc = ffi.gc


local LIB
local JQ_STATE


local function jv_gc(jv)
  return ffi_gc(jv, LIB.jv_free)
end


local function jv_string_value(jv)
  return ffi_string(LIB.jv_string_value(jv))
end


local function jv_dump_string(jv, flags)
  local jv_string = jv_gc(LIB.jv_dump_string(jv, flags or 0))
  if not jv_string then
    return nil, "dump string failed"
  end
  return jv_string_value(jv_string)
end


local function jv_error_string(e)
  local jv = jv_gc(e)
  local err_kind = LIB.jv_get_kind(jv)

  local err
  if err_kind == LIB.JV_KIND_STRING then
    err = jv_string_value(jv)

  elseif err_kind ~= LIB.JV_KIND_INVALID and err_kind ~= LIB.JV_KIND_NULL then
    err = jv_dump_string(jv)
  end

  return err or "unknown error"
end


local LF = "\n"

local DEFAULT_FILTER_OPTIONS = {
  compact_output = true,   -- set to false for pretty output
  raw_output     = false,  -- output strings raw, instead of quoted JSON
  join_output    = false,  -- as raw, but do not add newlines
  ascii_output   = false,  -- escape non-ASCII characters
  sort_keys      = false,  -- sort fields in each object
  table_output   = false,  -- return results in a sequence-like table instead of a string
}


local jq = {
  _VERSION = "0.2.0",
}

jq.__index = jq


function jq.new()
  if not JQ_STATE then
    LIB = require("resty.jq.lib")
    JQ_STATE = ffi.new("struct jq_state*[1]")
  end

  local context = LIB.jq_init()
  if not context then
    return nil, "unable to initialize jq state"
  end

  return setmetatable({
    context = context,
    compiled = false,
  }, jq)
end


function jq:teardown()
  JQ_STATE[0] = self.context
  LIB.jq_teardown(JQ_STATE)
  JQ_STATE[0] = nil
  self.context = nil
end


function jq:compile(program)
  local ctx = self.context
  if not ctx then
    return nil, "not initialized"
  end

  if LIB.jq_compile(ctx, program) ~= 1 then
    return nil, "compilation failed: invalid jq program"
  end

  self.compiled = true
  return true
end


local function check_filter_options(options)
  if type(options) ~= "table" then
    options = {}
  end

  options = setmetatable(options, { __index = DEFAULT_FILTER_OPTIONS })

  for k, _ in pairs(options) do
    if DEFAULT_FILTER_OPTIONS[k] == nil then
      return nil, k
    end

    local option_type = type(DEFAULT_FILTER_OPTIONS[k])
    if option_type and type(rawget(options, k)) ~= option_type then
      return nil, k .. " expects a " .. option_type
    end
  end

  if options.table_output then
    -- don't add newlines to the output buffer if returning a table
    if rawget(options, "join_output") == nil then
      options.join_output = true
    end

  elseif options.join_output then
    -- join_output implies raw_output
    options.raw_output = true
  end

  -- jq ignores raw output in ascii mode
  if options.ascii_output and options.raw_output then
    options.raw_output = false
  end

  return options
end


local function get_dump_flags(options)
  local dump_flags = 0
  if not options.compact_output then
    dump_flags = bor(dump_flags, LIB.JV_PRINT_PRETTY, LIB.JV_PRINT_SPACE1)
  end

  if options.ascii_output then
    dump_flags = bor(dump_flags, LIB.JV_PRINT_ASCII)
  end

  if options.sort_keys then
    dump_flags = bor(dump_flags, LIB.JV_PRINT_SORTED)
  end

  return dump_flags
end


function jq:filter(data, options, buf)
  local ctx = self.context
  if not ctx then
    return nil, "not initialized"
  end

  if not self.compiled then
    return nil, "unable to filter: program was not compiled"
  end

  if type(data) ~= "string" then
    return nil, "unable to filter: no input data was given"
  end

  if buf ~= nil then
    if type(buf) ~= "table" then
      return nil, "invalid buffer type"
    end

    options = options or {}

    if options.table_output == nil then
      options.table_output = true
    end
  end

  do
    local err
    options, err = check_filter_options(options)
    if not options then
      return nil, "invalid option: " .. err
    end
  end

  local dump_flags = get_dump_flags(options)

  local jv = LIB.jv_parse_sized(data, #data)
  if LIB.jv_get_kind(jv) == LIB.JV_KIND_INVALID then
    local msg
    if LIB.jv_invalid_has_msg(LIB.jv_copy(jv)) then
      local jv_msg = LIB.jv_invalid_get_msg(jv)
      msg = ffi_string(LIB.jv_string_value(jv_msg))
    else
      msg = "unknown parse error" -- should not be possible
    end

    return nil, "unable to filter: " .. msg
  end

  local debug_trace_flags = 0
  LIB.jq_start(ctx, jv, debug_trace_flags)

  buf = buf or {}
  local i = 0

  local jv_next

  while true do
    jv_next = LIB.jq_next(ctx)
    if not jv_next then
      return nil, "unable to filter: invalid next"
    end

    local kind = LIB.jv_get_kind(jv_next)
    if not kind then
      return nil, "unable to filter: invalid kind"
    end

    if kind == LIB.JV_KIND_INVALID then
      break

    elseif kind == LIB.JV_KIND_STRING and options.raw_output then
      i = i + 1
      buf[i] = jv_string_value(jv_next)

    else
      local str, err = jv_dump_string(jv_next, dump_flags)
      if not str then
        return nil, "unable to filter: " .. err
      end
      i = i + 1
      buf[i] = str
    end

    if not options.join_output then
      i = i + 1
      buf[i] = LF
    end
  end

  -- add a nil terminator in case we were passed in a reused buffer table
  buf[i + 1] = nil

  local ec = LIB.JQ_OK
  local err

  if LIB.jq_halted(ctx) == 1 then
    local jv_ec = jv_gc(LIB.jq_get_exit_code(ctx))
    local ec_kind = LIB.jv_get_kind(jv_ec)

    if ec_kind == LIB.JV_KIND_NUMBER then
      ec = LIB.jv_number_value(jv_ec)

    elseif ec_kind ~= LIB.JV_KIND_INVALID then
      ec = LIB.JQ_ERROR_UNKNOWN
    end

    if ec ~= LIB.JQ_OK then
      local msg = jv_error_string(LIB.jq_get_error_message(ctx))
      err = "filter halted: " .. msg
    end

  elseif LIB.jv_get_kind(jv_next) == LIB.JV_KIND_INVALID
    and LIB.jv_invalid_has_msg(LIB.jv_copy(jv_next)) == 1
  then
    ec = LIB.JQ_ERROR_UNKNOWN
    local msg = jv_error_string(LIB.jv_invalid_get_msg(LIB.jv_copy(jv_next)))
    err = "filter exception: " .. msg
  end

  if options.table_output then
    return buf, err, ec
  end

  return tbl_concat(buf, nil, 1, i), err, ec
end


return jq
