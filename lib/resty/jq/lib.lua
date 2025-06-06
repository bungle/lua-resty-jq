local ffi = require("ffi")


local error = error
local pcall = pcall
local ipairs = ipairs
local ffi_load = ffi.load


ffi.cdef([[
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
]])


local function load_lib(name)
  local pok, lib = pcall(ffi_load, name)
  if pok then
    return lib
  end
end


local load_lib_from_cpath do
  local gmatch = string.gmatch
  local match = string.match
  local open = io.open
  local close = io.close
  local cpath = package.cpath
  function load_lib_from_cpath(name)
    for path, _ in gmatch(cpath, "[^;]+") do
      if path == "?.so" or path == "?.dylib" then
        path = "./"
      end
      local file_path = match(path, "(.*/)")
      file_path = file_path .. name
      local file = open(file_path)
      if file ~= nil then
        close(file)
        local lib = load_lib(file_path)
        return lib
      end
    end
  end
end


do
  local library_names = {
    "libjq",
    "jq",
  }

  local library_extensions = ffi.os == "OSX" and { ".dylib", ".so", }
                                              or { ".so", ".dylib", }

  local library_versions = {
    "",
    ".1",
  }

  -- try to load ada library from package.cpath
  for _, library_name in ipairs(library_names) do
    for _, library_extension in ipairs(library_extensions) do
      for _, library_version in ipairs(library_versions) do
        local lib = load_lib_from_cpath(library_name .. library_extension .. library_version)
        if lib then
          return lib
        end
        lib = load_lib_from_cpath(library_name .. library_version .. library_extension)
        if lib then
          return lib
        end
      end
    end
  end

  -- try to load ada library from normal system path
  for _, library_name in ipairs(library_names) do
    for _, library_version in ipairs(library_versions) do
      local lib = load_lib(library_name .. library_version)
      if lib then
        return lib
      end
    end
  end

  -- a final check before we give up
  local pok, lib = pcall(function()
    if ffi.C.solClient_initialize then
      return ffi.C
    end
  end)
  if pok then
    return lib
  end
end


error("unable to load jq library - please make sure that it can be found in package.cpath or system library path")
