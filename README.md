**Json-rpc**

[![Build Status (Travis)](https://img.shields.io/travis/status-im/nim-eth-rpc/master.svg?label=Linux%20/%20macOS "Linux/macOS build status (Travis)")](https://travis-ci.org/status-im/nim-eth-rpc)
[![Windows build status (Appveyor)](https://img.shields.io/appveyor/ci/jarradh/nim-eth-rpc/master.svg?label=Windows "Windows build status (Appveyor)")](https://ci.appveyor.com/project/jarradh/nim-eth-rpc)

Json-Rpc is a library designed to provide an easier interface for working with remote procedure calls.

# Installation

`git clone https://github.com/status-im/nim-eth-rpc`


### Requirements
* Nim 17.3 and up


# Introduction

Json-Rpc is a library for routing JSON 2.0 format remote procedure calls over different transports.
It is designed to automatically generate marshalling and parameter checking code based on the RPC parameter types.

## Routing

Remote procedure calls are created using the `rpc` macro on an instance of `RpcRouter`.

`rpc` allows you to provide a list of native Nim type parameters and a return type, generates marshalling to and from json for you, so you can concentrate on using native Nim types for your call.

Routing is then performed by the `route` procedure.

When an error occurs, the `error` is populated, otherwise `result` will be populated.

### `route` Parameters

`path`: The string to match for the `method`.

`body`: The parameters and code to execute for this call.

### Example

Here's a simple example:

```nim
import rpcserver

var router = newRpcRouter()

router.rpc:
  result = %"Hello"
```

As no return type was specified in this example, `result` defaults to the `JsonNode` type.
A JSON string is returned by passing a string though the `%` operator, which converts simple types to `JsonNode`.

The `body` parameters can be defined by using [do notation](https://nim-lang.org/docs/manual.html#procedures-do-notation).
This allows full Nim types to be used as RPC parameters.

Here we pass a string to an RPC and return a string.

```nim
router.rpc("hello") do(input: string) -> string:
  result = "Hello " & input
```

Json-Rpc will recursively parse the Nim types in order to produce marshalling code.
This marshalling code uses the types to check the incoming JSON fields to ensure they exist and are of the correct kind.

The return type then performs the opposite process, converting Nim types to Json for transport.

Here is a more complex parameter example:

```nim
type
  HeaderKind = enum hkOne, hkTwo, hkThree
  
  Header = ref object
    kind: HeaderKind
    size: int64

  DataBlob = object
    items: seq[byte]
    headers: array[3, Header]

  MyObject = object
    data: DataBlob
    name: string

router.rpc("updateData") do(myObj: MyObject, newData: DataBlob) -> DataBlob:
  result = myObj.data  
  myObj.data = newData
```

Behind the scenes, all RPC calls take a single json parameter `param` that must be of kind `JArray`.
At runtime, the json is checked to ensure that it contains the correct number and type of your parameters to match the `rpc` definition.

Compiling with `-d:nimDumpRpcs` will show the output code for the RPC call. To see the output of the `async` generation, add `-d:nimDumpAsync`.

## JSON Format

The router expects either a string or `JsonNode` with the following structure:

```json
{
  "id": JInt,
  "jsonrpc": "2.0",
  "method": JString,
  "params": JArray
}
```

Return values use the following node structure:

```json
{
  "id": JInt,
  "jsonrpc": "2.0",
  "result": JsonNode,
  "error": JsonNode
}
```

## Performing a route

To call the router, use the `route` procedure.

There are three variants of `route`.

Note that once invoked all RPC calls are error trapped and any exceptions raised are passed back with the error message encoded as a `JsonNode`.

### `route` by string

This `route` variant will handle all the conversion of `string` to `JsonNode` and check the format and type of the input data.

#### Parameters

`router: RpcRouter`: The router object that contains the RPCs.

`data: string`: A string ready to be processed into a `JsonNode`.

#### Returns

`Future[string]`: This will be the stringified JSON response, which can be the JSON RPC result or a JSON wrapped error.
  

### `route` by `JsonNode`

This variant allows simplified processing if you already have a `JsonNode`. However if the required fields are not present within `node`, exceptions will be raised.

#### Parameters

`router: RpcRouter`: The router object that contains the RPCs.

`node: JsonNode`: A pre-processed JsonNode that matches the expected format as defined above.

#### Returns

`Future[JsonNode]`: The JSON RPC result or a JSON wrapped error.
  

### `tryRoute`

This `route` variant allows you to invoke a call if possible, without raising an exception.

#### Parameters

`router: RpcRouter`: The router object that contains the RPCs.

`node: JsonNode`: A pre-processed JsonNode that matches the expected format as defined above.

`fut: var Future[JsonNode]`: The JSON RPC result or a JSON wrapped error.

#### Returns

`bool`: `true` if the `method` field provided in `node` matches an available route. Returns `false` when the `method` cannot be found, or if `method` or `params` field cannot be found within `node`.
  

To see the result of a call, we need to provide Json in the expected format.
Here's an example of how that looks by manually creating the JSON. Later we will see the helper utilities that make this easier.

```nim
let call = %*{
  "id": %1,
  "jsonrpc": %2.0,
  "method": %"hello",
  "params": %["Terry"]
  }
# route the call we defined earlier
let localResult = waitFor router.route(call)

echo localResult
# We should see something like this
#   {"jsonrpc":"2.0","id":1,"result":"Hello Terry","error":null}
```

# Server

In order to make routing useful, RPCs must be invoked and transmitted over a transport.

The `RpcServer` type is given as a simple inheritable wrapper/container that simplifies designing your own transport layers using the `router` field.

## Server Transports

Currently there are plans for the following transports to be implemented:

* [x] Sockets
* [ ] HTTP
* [ ] IPC
* [ ] Websockets

Transport specific server need only call the `route` procedure using a string fetched from the transport in order to invoke the requested RPC.

## Server example

This example uses the socket transport defined in `socket.nim`.
Once executed, the "hello" RPC will be available to a socket based client.

```nim
import rpcserver

# Create a socket server for transport
var srv = newRpcSocketServer("localhost", Port(8585))

# srv.rpc is a shortcut for srv.router.rpc 
srv.rpc("hello") do(input: string) -> string:
  result = "Hello " & input

srv.start()
runForever()
```

# Client

Json-Rpc also comes with a client implementation, built to provide a framework for transports to work with.

To simplify demonstration, we will use the socket transport defined in `socketclient.nim`.

Below is the most basic way to use a remote call on the client.
Here we manually supply the name and json parameters for the call.

The `call` procedure takes care of the basic format of the JSON to send to the server.
However you still need to provide `params` as a `JsonNode`, which must exactly match the parameters defined in the equivalent `rpc` definition.

```nim
import rpcclient, rpcserver, asyncdispatch, json

var
  server = newRpcSocketServer("localhost", Port(8545))
  client = newRpcSocketClient()

server.start

server.rpc("hello") do(input: string) -> string:
  result = "Hello " & input

waitFor client.connect("localhost", Port(8545))

let response = waitFor client.call("hello", %[%"Daisy"])

# the call returns a `Response` type which contains the result
echo response.result
```

### `createRpcSigs`

To make things more readable and allow better static checking client side, Json-Rpc supports generating wrappers for client RPCs using `createRpcSigs`.

This macro takes a type name and the path of a file containing forward declarations of procedures that you wish to convert to client RPCs. The transformation generates procedures that match the forward declarations provided, plus a `client` parameter in the specified type.

Because the signatures are parsed at compile time, the file will be error checked and you can use import to share common types between your client and server.

#### Parameters

`clientType`: This is the type you want to pass to your generated calls. Usually this would be a transport specific descendant from `RpcClient`.

`path`: The path to the Nim module that contains the RPC header signatures.

#### Example

For example, to support this remote call:

```nim
server.rpc("bmi") do(height, weight: float) -> float:
  result = (height * height) / weight
```

You can have the following in your rpc signature file:

```nim
proc bmi(height, weight: float): float
```

When parsed through `createRpcSigs`, you can call the RPC as if it were a normal procedure.
So instead of this:

```nim
let bmiIndex = await client.call("bmi", %[%120.5, %12.0])
```

You can use:

```nim
let bmiIndex = await client.bmi(120.5, 12.0)
```

This allows you to leverage Nim's static type checking whilst also aiding readability and providing a unified location to declare client side RPC definitions.

## Working with client transports

Transport clients should provide a type that is inherited from `RpcClient` where they can store any transport related information.

Additionally, the following two procedures are useful:

* `Call`

  `self`: a descendant of `RpcClient`
  `name: string`: the method to be called
  `params: JsonNode`: The parameters to the RPC call
  Returning
    `Future[Response]`: A wrapper for the result `JsonNode` and a flag to indicate if this contains an error.

Note: Although `call` isn't necessary for a client to function, it allows RPC signatures to be used by the `createRpcSigs`.

* `Connect`

  `client`: a descendant of `RpcClient`
  Returning
    `FutureBase`: The base future returned when a procedure is annoted with `{.async.}`

### `processMessage`

To simplify and unify processing within the client, the `processMessage` procedure can be used to perform conversion and error checking from the received string originating from the transport to the `JsonNode` representation that is passed to the RPC.

After a RPC returns, this procedure then completes the futures set by `call` invocations using the `id` field of the processed `JsonNode` from `line`.

#### Parameters

`self`: a client type descended from `RpcClient`

`line: string`: a string that contains the JSON to be processed


# Contributing
Pull requests are welcome. For major changes, please open an issue first to discuss what you would like to change.

Please make sure to update tests as appropriate.

# License
[MIT](https://choosealicense.com/licenses/mit/)
or
Apache License, Version 2.0, ([LICENSE-APACHE](LICENSE-APACHE) or http://www.apache.org/licenses/LICENSE-2.0)