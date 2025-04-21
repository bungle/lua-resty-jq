# lua-resty-jq

**lua-resty-jq** is a small LuaJIT FFI wrapper to [jq](https://stedolan.github.io/jq/)


## Hello World with lua-resty-jq

```lua
-- <example-input> from https://api.github.com/repos/stedolan/jq/commits?per_page=5
local jq = require "resty.jq".new()

jq:compile("[ .[] | {message: .commit.message, name: .commit.committer.name} ]")
local output = jq:filter(<example-input>)

print(output)

jq:teardown()
```

Running the above code will output (or similar):

```javascript
[
  {
    "message": "Add some missing code quoting to the manual",
    "name": "William Langford"
  },
  {
    "message": "Reduce allocation on string multiplication",
    "name": "William Langford"
  },
  {
    "message": "Fix multiple string multiplication",
    "name": "William Langford"
  },
  {
    "message": "Fix error handling in strftime",
    "name": "William Langford"
  },
  {
    "message": "Makefile: prepend srcdir to jq.1.prebuilt to fix out of source compilation",
    "name": "William Langford"
  }
]
```

## new

`syntax: jq, err = require("resty.jq").new()`

Allocates a `libjq` context.

## teardown

`syntax: jq:teardown()`

Destroys the `libjq` context, freeing resources.

## compile

`syntax: ok, err = jq:compile(program)`

Returns `true` if the program was compiled, otherwise `nil` and the error
`compilation failed`.

Note it is not currently possible to inspect details of the compilation error.
If in doubt, try your program in the CLI `jq`.

## filter

`syntax: res, err = jq:filter(data, options)`

Filters `data` using the previously compiled program. The `options` table can
contain flags which alter the behaviour of the filter, similar to a subset of
the CLI options to `jq`:

* `compact_output`: Returns output in a compact form without additional
  spacing, and with each JSON object on a single line. Defaults to `true`. Set
to `false` for "pretty" output.
* `raw_output`: Outputs as raw strings, not JSON quoted. Default is `false`.
* `join_output`: As `raw_output` but in addition does not output newline
  separators. Default is `false`.
* `ascii_output`: jq usually outputs non-ASCII Unicode codepoints as UTF-8,
  even if the input specified them as escape sequences (like "\u03bc"). Using
this option, you can force jq to produce pure ASCII output with every non-ASCII
character replaced with the equivalent escape sequence. Default is `false`.
* `sort_keys`: Output the fields of each object with the keys in sorted order.
  Default is `false`.
* `table_output`: Returns a sequence-like table of encoded results instead of
    concatenating them into a single string. Default is `false`.

Additionally, `filter()` takes a table as an optional 3rd argument. When
supplied, this table will be used to store results instead of creating a new
table for each call to `filter()`:

```lua
local buf = {}
local res, err = jq:filter(data, nil, buf)
for _, elem in ipairs(buf) do
  -- ...
end
```

Doing so implies `options.table_output = true`, so this option must be
explicitly set to `false` in order to receive a string result:

```lua
local buf = {}
local res, err = jq:filter(data, { table_output = false }, buf)
print(res)
```

**NOTE:** `filter()` adds a trailing `nil` to the table such that the length
operator (`#buf`) and `ipairs(buf)` return accurate results after execution, but
it does _not_ clear the table. Callers must clear the table themselves if
desired.

## See Also

* [lua-jq](https://github.com/tibbycat/lua-jq)


## License

`lua-resty-jq` uses two clause BSD license.

```
Copyright (c) 2020 – 2021 Aapo Talvensaari, James Hurst
All rights reserved.

Redistribution and use in source and binary forms, with or without modification,
are permitted provided that the following conditions are met:

* Redistributions of source code must retain the above copyright notice, this
  list of conditions and the following disclaimer.

* Redistributions in binary form must reproduce the above copyright notice, this
  list of conditions and the following disclaimer in the documentation and/or
  other materials provided with the distribution.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR
ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
```
