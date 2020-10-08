# lua-resty-jq

**lua-resty-jq** is a small LuaJIT FFI wrapper to [jq](https://stedolan.github.io/jq/)


## Hello World with lua-resty-jq

```lua
-- <example-input> from https://api.github.com/repos/stedolan/jq/commits?per_page=5
local jq =  require "resty.jq".new()

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


## See Also

* [lua-jq](https://github.com/tibbycat/lua-jq)


## License

`lua-resty-session` uses two clause BSD license.

```
Copyright (c) 2020 Aapo Talvensaari
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
