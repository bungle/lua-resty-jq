local ffi = require "ffi"


local bor = bit.bor
local type = type
local pairs = pairs
local rawget = rawget
local tbl_concat = table.concat
local setmetatable = setmetatable
local ffi_string = ffi.string
local ffi_gc = ffi.gc


ffi.cdef [[
typedef enum {
  JV_KIND_INVALID,
  JV_KIND_NULL,
  JV_KIND_FALSE,
  JV_KIND_TRUE,
  JV_KIND_NUMBER,
  JV_KIND_STRING,
  JV_KIND_ARRAY,
  JV_KIND_OBJECT
} jv_kind;

typedef enum {
  JV_PRINT_PRETTY   = 1,
  JV_PRINT_ASCII    = 2,
  JV_PRINT_COLOR    = 4, JV_PRINT_COLOUR = 4,
  JV_PRINT_SORTED   = 8,
  JV_PRINT_INVALID  = 16,
  JV_PRINT_REFCOUNT = 32,
  JV_PRINT_TAB      = 64,
  JV_PRINT_ISATTY   = 128,
  JV_PRINT_SPACE0   = 256,
  JV_PRINT_SPACE1   = 512,
  JV_PRINT_SPACE2   = 1024,
} jv_print_flags;

enum {
    JQ_OK              =  0,
    JQ_OK_NULL_KIND    = -1, /* exit 0 if --exit-status is not set*/
    JQ_ERROR_SYSTEM    =  2,
    JQ_ERROR_COMPILE   =  3,
    JQ_OK_NO_OUTPUT    = -4, /* exit 0 if --exit-status is not set*/
    JQ_ERROR_UNKNOWN   =  5,
};

typedef struct {
  unsigned char kind_flags;
  unsigned char pad_;
  unsigned short offset;
  int size;
  union {
    struct jv_refcnt* ptr;
    double number;
  } u;
} jv;

typedef struct jq_state jq_state;

jq_state *jq_init(void);
int jq_compile(jq_state *, const char*);
void jq_start(jq_state *, jv value, int);
void jq_teardown(jq_state **);
void jv_free(jv);
jv jq_next(jq_state *);
jv jv_parse_sized(const char* string, int length);
jv jv_dump_string(jv, int flags);
int jv_invalid_has_msg(jv);
jv jv_invalid_get_msg(jv);
jv jv_copy(jv);
jv_kind jv_get_kind(jv);
const char* jv_string_value(jv);
int jq_halted(jq_state *);
jv jq_get_exit_code(jq_state *);
jv jq_get_error_message(jq_state *);
double jv_number_value(jv);
jv jq_util_input_get_position(jq_state*);
]]


local lib = ffi.load "jq"
local arr = ffi.new("struct jq_state*[1]")


local function jv_gc(jv)
  return ffi_gc(jv, lib.jv_free)
end


local function jv_string_value(jv)
  return ffi_string(lib.jv_string_value(jv))
end


local function jv_dump_string(jv, flags)
  local jv_string = jv_gc(lib.jv_dump_string(jv, flags or 0))
  if not jv_string then
    return nil, "dump string failed"
  end
  return jv_string_value(jv_string)
end


local function jv_error_string(e)
  local jv = jv_gc(e)
  local err_kind = lib.jv_get_kind(jv)

  local err
  if err_kind == lib.JV_KIND_STRING then
    err = jv_string_value(jv)

  elseif err_kind ~= lib.JV_KIND_INVALID and err_kind ~= lib.JV_KIND_NULL then
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
  _VERSION = "0.1.0",
}

jq.__index = jq


function jq.new()
  local context = lib.jq_init()
  if not context then
    return nil, "unable to initialize jq state"
  end

  return setmetatable({
    context = context,
    compiled = false,
  }, jq)
end


function jq:teardown()
  arr[0] = self.context
  lib.jq_teardown(arr)
  arr[0] = nil
  self.context = nil
end


function jq:compile(program)
  local ctx = self.context
  if not ctx then
    return nil, "not initialized"
  end

  if lib.jq_compile(ctx, program) ~= 1 then
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
    dump_flags = bor(dump_flags, lib.JV_PRINT_PRETTY, lib.JV_PRINT_SPACE1)
  end

  if options.ascii_output then
    dump_flags = bor(dump_flags, lib.JV_PRINT_ASCII)
  end

  if options.sort_keys then
    dump_flags = bor(dump_flags, lib.JV_PRINT_SORTED)
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

  local jv = lib.jv_parse_sized(data, #data)
  if lib.jv_get_kind(jv) == lib.JV_KIND_INVALID then
    local msg
    if lib.jv_invalid_has_msg(lib.jv_copy(jv)) then
      local jv_msg = lib.jv_invalid_get_msg(jv)
      msg = ffi_string(lib.jv_string_value(jv_msg))
    else
      msg = "unknown parse error" -- should not be possible
    end

    return nil, "unable to filter: " .. msg
  end

  local debug_trace_flags = 0
  lib.jq_start(ctx, jv, debug_trace_flags)

  buf = buf or {}
  local i = 0

  local jv_next

  while true do
    jv_next = lib.jq_next(ctx)
    if not jv_next then
      return nil, "unable to filter: invalid next"
    end

    local kind = lib.jv_get_kind(jv_next)
    if not kind then
      return nil, "unable to filter: invalid kind"
    end

    if kind == lib.JV_KIND_INVALID then
      break

    elseif kind == lib.JV_KIND_STRING and options.raw_output then
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

  local ec = lib.JQ_OK
  local err

  if lib.jq_halted(ctx) == 1 then
    local jv_ec = jv_gc(lib.jq_get_exit_code(ctx))
    local ec_kind = lib.jv_get_kind(jv_ec)

    if ec_kind == lib.JV_KIND_NUMBER then
      ec = lib.jv_number_value(jv_ec)

    elseif ec_kind ~= lib.JV_KIND_INVALID then
      ec = lib.JQ_ERROR_UNKNOWN
    end

    if ec ~= lib.JQ_OK then
      local msg = jv_error_string(lib.jq_get_error_message(ctx))
      err = "filter halted: " .. msg
    end

  elseif lib.jv_get_kind(jv_next) == lib.JV_KIND_INVALID
    and lib.jv_invalid_has_msg(lib.jv_copy(jv_next)) == 1
  then
    ec = lib.JQ_ERROR_UNKNOWN
    local msg = jv_error_string(lib.jv_invalid_get_msg(lib.jv_copy(jv_next)))
    err = "filter exception: " .. msg
  end

  if options.table_output then
    return buf, err, ec
  end

  return tbl_concat(buf, nil, 1, i), err, ec
end


return jq
