local ffi = require "ffi"


local type = type
local table = table
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
jv_kind jv_get_kind(jv);
const char* jv_string_value(jv);
]]


local lib = ffi.load "jq"
local arr = ffi.new("struct jq_state*[1]")
local ecb = ffi.cast("jq_msg_cb *", function() end)
local mcb = ffi.cast("void (*)(void *)", function() end)


local LF = "\n"


local jq = {
    _VERSION = "0.1"
}


jq.__index = jq


function jq.new()
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
  if lib.jq_compile(ctx, program) ~= 1 then
    self.error = "compilation failed"
  end

  self.compiled = true

  return true
end


function jq:filter(data, opts)
  local dump = 0
  local flags = 0
  local raw = false
  local join = false
  if type(opts) == "table" then
    if opts.dump then
      if type(opts.dump) ~= "number" then
        return nil, "invalid option: dump"
      end

      dump = opts.dump
    end

    if opts.flags then
      if type(opts.flags) ~= "number" then
        return nil, "invalid option: flags"
      end

      flags = opts.flags
    end

    if opts.raw then
      if type(opts.raw) ~= "boolean" then
        return nil, "invalid option: raw"
      end

      raw = opts.raw
    end

    if opts.join then
      if type(opts.join) ~= "boolean" then
        return nil, "invalid option: join"
      end

      join = opts.raw_no_lf
    end
  end

  if self.error then
    return nil, "unable to transform: " .. self.error
  end

  if not self.compiled then
    return nil, "unable to transform: program was not compiled"
  end

  local ctx = self.context
  local buf = {}
  local i = 0
  local jv = lib.jv_parse_sized(data, #data)
  if not jv then
    return nil, "unable to filter: parse failed"
  end

  lib.jq_start(ctx, jv, flags)

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

    elseif kind == lib.JV_KIND_STRING and raw then
      i = i + 1
      buf[i] = ffi.string(lib.jv_string_value(jv_next))

    else
      local jv_string = ffi.gc(lib.jv_dump_string(jv_next, dump), lib.jv_free)
      if not jv_string then
        return nil, "unable to filter: dump string failed"
      end
      i = i + 1
      buf[i] = ffi.string(lib.jv_string_value(jv_string))
    end

    if not join then
      i = i + 1
      buf[i] = LF
    end
  end

  return table.concat(buf, nil, 1, i)
end


return jq
