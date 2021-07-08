describe("jq ffi", function()
  describe("module:", function()
    local jq = require "resty.jq"
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
    local jq = require("resty.jq").new()

    it("creates new context", function()
      assert.truthy(jq)
      assert.is_nil(err)
    end)

    it("tears down context", function()
      jq:teardown()

      local res, err = jq:compile(".")
      assert.falsy(res)
      assert.same("not initialized", err)

      local jq = require("resty.jq").new()
      local res, err = jq:compile(".")
      assert.truthy(res)
      assert.is_nil(err)

      jq:teardown()

      local res, err = jq:filter("[]")
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

      local res, err = jq:filter("[]", { join_output = "" })
      assert.same(err, "invalid option: join_output expects a boolean")
      assert.falsy(res)
    end)

    it("fails to filter with bad input", function()
      local res, err = jq:filter("[")
      assert.same(err, "unable to filter: parse failed")
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
    local jq, err = require("resty.jq").new()

    it("raw_output", function()
      jq:compile(".foo")

      local res, err = jq:filter([[{"foo": "bar"}]], { raw_output = false })
      assert.is_nil(err)
      assert.truthy(res)
      assert.same("\"bar\"\n", res)

      local res, err = jq:filter([[{"foo": "bar"}]], { raw_output = true })
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

      local res, err = jq:filter([[{"foo": "42"}]], { join_output = true })
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

      local res, err = jq:filter([[{"foo": "bar"}]],{ compact_output = false })
      assert.is_nil(err)
      assert.truthy(res)
      assert.same([[{
  "foo": "bar"
}
]], res)
    end)
  end)
end)
