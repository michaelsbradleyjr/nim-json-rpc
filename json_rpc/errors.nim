import std/json

type
  JsonRpcError* = object of CatchableError
    ## Base type of all nim-json-rpc errors

  ErrorResponse* = object of JsonRpcError
    ## raised when the server responded with an error

  InvalidResponse* = object of JsonRpcError
    ## raised when the server response violates the JSON-RPC protocol

  FailedHttpResponse* = object of JsonRpcError
    ## raised when fail to read the underlying HTTP server response

  RpcPostError* = object of JsonRpcError
    ## raised when the client fails to send the POST request with JSON-RPC

  RpcBindError* = object of JsonRpcError
  RpcAddressUnresolvableError* = object of JsonRpcError

  InvalidRequest* = object of JsonRpcError
    ## This could be raised by request handlers when the server
    ## needs to respond with a custom error code.
    code*: int

  InvalidRequestWithData* = object of InvalidRequest
    ## This could be raised by request handlers when the server needs to
    ## respond with a custom error code and data.
    data*: JsonNode
