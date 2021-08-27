local ffi = require "ffi"


local type = type
local tbl_concat = table.concat
local setmetatable = setmetatable


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
typedef void *jq_msg_cb(void *, jv*);

void jq_set_error_cb(jq_state *, jq_msg_cb, void *);
void jq_set_nomem_handler(jq_state *, void (*)(void *), void *);

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
]]


local lib = ffi.load "jq"
local arr = ffi.new("struct jq_state*[1]")
local ecb = ffi.cast("jq_msg_cb *", function() end)
local mcb = ffi.cast("void (*)(void *)", function() end)


local LF = "\n"

local DEFAULT_FILTER_OPTIONS = {
  compact_output = true,   -- set to false for pretty output
  raw_output     = false,  -- output strings raw, instead of quoted JSON
  join_output    = false,  -- as raw, but do not add newlines
  ascii_output   = false,  -- escape non-ASCII characters
  sort_keys      = false,  -- sort fields in each object
}


local jq = {
  _VERSION = "0.1",
}

jq.__index = jq


function jq.new()
  -- It's important that this function is not jit compiled, since we pass Lua
  -- callbacks to a C function, which will be called in error scenarios. LuaJIT
  -- mostly knows how to spot this, but in some scenarious (inc. OpenResty) it
  -- can sometimes crash the VM if we don't give it this hint.
  jit.off()

  local context = lib.jq_init()
  if not context then
    return nil, "unable to initialize jq state"
  end

  lib.jq_set_error_cb(context, ecb, nil)
  lib.jq_set_nomem_handler(context, mcb, nil)

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
    return nil, "compilation failed"
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

  -- join_output implies raw_output
  if options.join_output then
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
    dump_flags = bit.bor(dump_flags, lib.JV_PRINT_PRETTY, lib.JV_PRINT_SPACE1)
  end

  if options.ascii_output then
    dump_flags = bit.bor(dump_flags, lib.JV_PRINT_ASCII)
  end

  if options.sort_keys then
    dump_flags = bit.bor(dump_flags, lib.JV_PRINT_SORTED)
  end

  return dump_flags
end


function jq:filter(data, options)
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
      msg = ffi.string(lib.jv_string_value(jv_msg))
    else
      msg = "unknown parse error" -- should not be possible
    end

    return nil, "unable to filter: " .. msg
  end

  local debug_trace_flags = 0
  lib.jq_start(ctx, jv, debug_trace_flags)

  local buf = {}
  local i = 0

  while true do
    local jv_next = lib.jq_next(ctx)
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
      buf[i] = ffi.string(lib.jv_string_value(jv_next))

    else
      local jv_string = ffi.gc(lib.jv_dump_string(jv_next, dump_flags), lib.jv_free)
      if not jv_string then
        return nil, "unable to filter: dump string failed"
      end
      i = i + 1
      buf[i] = ffi.string(lib.jv_string_value(jv_string))
    end

    if not options.join_output then
      i = i + 1
      buf[i] = LF
    end
  end

  return tbl_concat(buf, nil, 1, i)
end


return jq
