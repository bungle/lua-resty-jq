describe("jq ffi", function()
  describe("module:", function()
    local jq, err = require "resty.jq"
    it("loads module", function()
      assert.truthy(jq)
      assert.is_nil(err)
    end)

    it("has a _VERSION", function()
      assert.is_string(jq._VERSION)
    end)

    it("has expected methods", function()
      assert.is_function(jq.new)
      assert.is_function(jq.teardown)
      assert.is_function(jq.compile)
      assert.is_function(jq.filter)
    end)
  end)

  describe("initialisation:", function()
    local jq, err = require("resty.jq").new()

    it("creates new context", function()
      assert.truthy(jq)
      assert.is_nil(err)
    end)

    it("tears down context", function()
      jq:teardown()

      local res
      res, err = jq:compile(".")
      assert.falsy(res)
      assert.same("not initialized", err)

      jq = require("resty.jq").new()
      res, err = jq:compile(".")
      assert.truthy(res)
      assert.is_nil(err)

      jq:teardown()

      res, err = jq:filter("[]")
      assert.falsy(res)
      assert.same("not initialized", err)
    end)
  end)

  describe("compilation:", function()
    it("fails to compile a bad program", function()
      local jq = require("resty.jq").new()
      local res, err = jq:compile(".[")
      assert.falsy(res)
      assert.same("compilation failed: invalid jq program", err)
    end)

    it("refuses to filter an uncompiled program", function()
      local jq = require("resty.jq").new()
      local res, err = jq:filter("[]")
      assert.falsy(res)
      assert.same("unable to filter: program was not compiled", err)
    end)

    it("compiles a valid program", function()
      local jq = require("resty.jq").new()
      local res, err = jq:compile(".")
      assert.truthy(res)
      assert.is_nil(err)
    end)
  end)

  describe("filter:", function()
    local jq = require("resty.jq").new()
    jq:compile(".foo")

    it("fails to filter with bad options", function()
      local res, err = jq:filter("[]", { raw_output = "" })
      assert.same(err, "invalid option: raw_output expects a boolean")
      assert.falsy(res)

      res, err = jq:filter("[]", { join_output = "" })
      assert.same(err, "invalid option: join_output expects a boolean")
      assert.falsy(res)
    end)

    it("fails to filter with bad input", function()
      local res, err = jq:filter("[")
      assert.same(err, "unable to filter: Unfinished JSON term at EOF at line 1, column 1 (while parsing '[')")
      assert.falsy(res)
    end)

    it("fails to filter with no input", function()
      local res, err = jq:filter()
      assert.same(err, "unable to filter: no input data was given")
      assert.falsy(res)
    end)

    it("filters with good input", function()
      local res, err = jq:filter([[{"foo": 42, "bar": "less interesting data"}]])
      assert.truthy(res)
      assert.is_nil(err)
      assert.same("42\n", res)
    end)

    it("reuses an optional buffer table", function()
      local stream = require("resty.jq").new()
      assert(stream:compile(".arr[]"))

      local data = [[{ "arr": [ "x", "y", { "z": 2 } ] } ]]
      local buf = {}
      local res, err = stream:filter(data, nil, buf)
      assert.truthy(res)
      assert.is_nil(err)

      -- this is explicitly an == check to validate that the same table
      -- was returned
      assert.equals(buf, res)

      assert.same({ [["x"]], [["y"]], [[{"z":2}]] }, buf)
    end)

    it("validates the reusable buffer table input", function()
      local res, err = jq:filter("{}", nil, "not a table")
      assert.falsy(res)
      assert.string(err)
      assert.matches("invalid buffer type", err)
    end)

    it("adds a trailing nil to the buffer to ensure the length operator works correctly", function()
      local stream = require("resty.jq").new()
      assert(stream:compile(".arr[]"))

      local data = [[{ "arr": [ "x", "y", { "z": 2 } ] } ]]
      local buf = { "a", "b", "c", "d", "e" }
      local res, err = stream:filter(data, nil, buf)
      assert.truthy(res)
      assert.is_nil(err)

      -- same table returned
      assert.equals(buf, res)

      assert.equals(3, #buf)
      assert.same({ [["x"]], [["y"]], [[{"z":2}]], nil, "e" }, buf)

      local c = 0
      for _ in ipairs(buf) do
        c = c + 1
      end
      assert.equals(3, c)
    end)
  end)

  describe("options:", function()
    local jq = require("resty.jq").new()

    it("raw_output", function()
      jq:compile(".foo")

      local res, err = jq:filter([[{"foo": "bar"}]], { raw_output = false })
      assert.is_nil(err)
      assert.truthy(res)
      assert.same("\"bar\"\n", res)

      res, err = jq:filter([[{"foo": "bar"}]], { raw_output = true })
      assert.is_nil(err)
      assert.truthy(res)
      assert.same("bar\n", res)
    end)

    it("join_output", function()
      jq:compile(".foo")

      local res, err = jq:filter([[{"foo": "bar"}]], { join_output = false })
      assert.is_nil(err)
      assert.truthy(res)
      assert.same("\"bar\"\n", res)

      res, err = jq:filter([[{"foo": "42"}]], { join_output = true })
      assert.is_nil(err)
      assert.truthy(res)
      assert.same("42", res)
    end)

    it("compact_output", function()
      jq:compile(".")

      local res, err = jq:filter([[{"foo": "bar"}]], { compact_output = true })
      assert.is_nil(err)
      assert.truthy(res)
      assert.same("{\"foo\":\"bar\"}\n", res)

      res, err = jq:filter([[{"foo": "bar"}]],{ compact_output = false })
      assert.is_nil(err)
      assert.truthy(res)
      assert.same([[{
  "foo": "bar"
}
]], res)
    end)

    it("ascii_output", function()
      jq:compile(".")

      local res, err = jq:filter([[{"foo": "baré"}]], { ascii_output = false })
      assert.is_nil(err)
      assert.truthy(res)
      assert.same("{\"foo\":\"baré\"}\n", res)

      res, err = jq:filter([[{"foo": "baré"}]], { ascii_output = true })
      assert.is_nil(err)
      assert.truthy(res)
      assert.same("{\"foo\":\"bar\\u00e9\"}\n", res)
    end)

    it("ascii_output && raw_output, raw is ignored", function()
      jq:compile(".foo")

      local res, err = jq:filter([[{"foo": "baré"}]], { ascii_output = true, raw_output = true })
      assert.is_nil(err)
      assert.truthy(res)
      assert.same("\"bar\\u00e9\"\n", res)
    end)

    it("ascii_output && join_output, implied raw is ignored", function()
      jq:compile(".foo")

      local res, err = jq:filter([[{"foo": "baré"}]], { ascii_output = true, join_output = true })
      assert.is_nil(err)
      assert.truthy(res)
      assert.same("\"bar\\u00e9\"", res)
    end)

    it("sort_keys", function()
      jq:compile(".")

      local res, err = jq:filter([[{"foo": "bar", "bar": "foo"}]], { sort_keys = false })
      assert.is_nil(err)
      assert.truthy(res)
      assert.same("{\"foo\":\"bar\",\"bar\":\"foo\"}\n", res)

      res, err = jq:filter([[{"foo": "bar", "bar": "foo"}]], { sort_keys = true })
      assert.is_nil(err)
      assert.truthy(res)
      assert.same("{\"bar\":\"foo\",\"foo\":\"bar\"}\n", res)
    end)

    it("table_output", function()
      jq:compile(".arr[]")

      local data = [[{ "arr": [ "x", "y", { "z": 2 } ] } ]]
      local res, err = jq:filter(data, { table_output = true })
      assert.truthy(res)
      assert.is_nil(err)
      assert.is_table(res)
      assert.same({ [["x"]], [["y"]], [[{"z":2}]] }, res)
    end)

    it("table_output enabled by default for reused buffer table", function()
      jq:compile(".arr[]")

      local data = [[{ "arr": [ "x", "y", { "z": 2 } ] } ]]
      local buf = {}
      local options = {}
      local res, err = jq:filter(data, options, buf)
      assert.truthy(res)
      assert.is_nil(err)
      assert.is_table(res)
      assert.same({ [["x"]], [["y"]], [[{"z":2}]] }, res)
      assert.truthy(options.table_output)
    end)

    it("table_output = false with reused buffer table", function()
      jq:compile(".arr[]")

      local data = [[{ "arr": [ "x", "y", { "z": 2 } ] } ]]
      local buf = {}
      local res, err = jq:filter(data, { table_output = false }, buf)
      assert.truthy(res)
      assert.is_nil(err)
      assert.is_string(res)
    end)
  end)
end)
