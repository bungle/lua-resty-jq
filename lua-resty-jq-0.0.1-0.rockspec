package = "lua-resty-jq"
version = "0.0.1-0"

source = {
  url = "https://github.com/bundle/lua-resty-jq",
  tag = "0.0.1"
}

description = {
  summary = "LuaJIT FFI bindings to libjq",
  license = "BSD",
}

dependencies = {
  "lua == 5.1"; -- Really "luajit >= 2.0.2"
}

build = {
  type = "builtin",
  modules = {
    ["resty.jq"] = "lib/resty/jq.lua",
  }
}