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
      assert.same("compilation failed", err)
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
  end)
end)
