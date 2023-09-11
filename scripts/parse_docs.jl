using Markdown

typemap = Dict("string" => :String, "bool" => :Bool, "int" => :Int, "uint64" => :UInt64, "[string]" => :(Vector{String}))

function parse_operations(operations)
    parse_row(row) = (name = row[1][1].text[1].code)
    ops = map(parse_row, operations.content[1].rows[2:end])
    ops = map(op -> strip(op, ['+', '-']), ops)
    Expr(:macrocall, Symbol("@enum"), :(), :ProtocolOperation, Symbol.(ops)...)
end


function parse_row(row)
    parse_row(row) = (name = row[1][1].code, type = row[3][1], presence = row[4][1])
    (name, type, presence) = parse_row(row)
    name = replace(name, "-" => "_", " " => "_", "#" => "")
    prop_type = typemap[type]
    if presence != "always" && presence != "true"
        prop_type = Expr(:curly, :Union, prop_type, :Nothing)
    end
    Expr(:(::), Symbol(name), prop_type)
end

function parse_markdown(md::Markdown.MD, struct_name::Symbol)
    expr = quote
        struct $struct_name <: ProtocolMessage
            $(map(parse_row, md.content[1].rows[2:end])...)
        end
    end
    expr = Base.remove_linenums!(expr)
    expr.args[1]
end

operations = md"""
| OP Name                 | Sent By | Description                                                                        |
|-------------------------|---------|------------------------------------------------------------------------------------|
| [`INFO`](./#info)       | Server  | Sent to client after initial TCP/IP connection                                     |
| [`CONNECT`](./#connect) | Client  | Sent to server to specify connection information                                   |
| [`PUB`](./#pub)         | Client  | Publish a message to a subject, with optional reply subject                        |
| [`HPUB`](./#hpub)       | Client  | Publish a message to a subject including NATS headers, with optional reply subject |
| [`SUB`](./#sub)         | Client  | Subscribe to a subject (or subject wildcard)                                       |
| [`UNSUB`](./#unsub)     | Client  | Unsubscribe (or auto-unsubscribe) from subject                                     |
| [`MSG`](./#msg)         | Server  | Delivers a message payload to a subscriber                                         |
| [`HMSG`](./#hmsg)       | Server  | Delivers a message payload to a subscriber with NATS headers                       |
| [`PING`](./#pingpong)   | Both    | PING keep-alive message                                                            |
| [`PONG`](./#pingpong)   | Both    | PONG keep-alive response                                                           |
| [`+OK`](./#okerr)       | Server  | Acknowledges well-formed protocol message in `verbose` mode                        |
| [`-ERR`](./#okerr)      | Server  | Indicates a protocol error. May cause client disconnect.                           |
"""

# FIXME: duplicated client_id, report bug to nats docs.
# | `client_id`       | The ID of the client.                                                                                                                                                  | string   | optional |
info = md"""
| name              | description                                                                                                                                                            | type     | presence |
|-------------------|------------------------------------------------------------------------------------------------------------------------------------------------------------------------|----------|----------|
| `server_id`       | The unique identifier of the NATS server.                                                                                                                              | string   | always   |
| `server_name`     | The name of the NATS server.                                                                                                                                           | string   | always   |
| `version`         | The version of NATS.                                                                                                                                                   | string   | always   |
| `go`              | The version of golang the NATS server was built with.                                                                                                                  | string   | always   |
| `host`            | The IP address used to start the NATS server, by default this will be `0.0.0.0` and can be configured with `-client_advertise host:port`.                              | string   | always   |
| `port`            | The port number the NATS server is configured to listen on.                                                                                                            | int      | always   |
| `headers`         | Whether the server supports headers.                                                                                                                                   | bool     | always   |
| `max_payload`     | Maximum payload size, in bytes, that the server will accept from the client.                                                                                           | int      | always   |
| `proto`           | An integer indicating the protocol version of the server. The server version 1.2.0 sets this to `1` to indicate that it supports the "Echo" feature.                   | int      | always   |
| `client_id`       | The internal client identifier in the server. This can be used to filter client connections in monitoring, correlate with error logs, etc...                           | uint64   | optional |
| `auth_required`   | If this is true, then the client should try to authenticate upon connect.                                                                                              | bool     | optional |
| `tls_required`    | If this is true, then the client must perform the TLS/1.2 handshake. Note, this used to be `ssl_required` and has been updated along with the protocol from SSL to TLS.| bool     | optional |
| `tls_verify`      | If this is true, the client must provide a valid certificate during the TLS handshake.                                                                                 | bool     | optional |
| `tls_available`   | If this is true, the client can provide a valid certificate during the TLS handshake.                                                                                  | bool     | optional |
| `connect_urls`    | List of server urls that a client can connect to.                                                                                                                      | [string] | optional |
| `ws_connect_urls` | List of server urls that a websocket client can connect to.                                                                                                            | [string] | optional |
| `ldm`             | If the server supports _Lame Duck Mode_ notifications, and the current server has transitioned to lame duck, `ldm` will be set to `true`.                              | bool     | optional |
| `git_commit`      | The git hash at which the NATS server was built.                                                                                                                       | string   | optional |
| `jetstream`       | Whether the server supports JetStream.                                                                                                                                 | bool     | optional |
| `ip`              | The IP of the server.                                                                                                                                                  | string   | optional |
| `client_ip`       | The IP of the client.                                                                                                                                                  | string   | optional |
| `nonce`           | The nonce for use in CONNECT.                                                                                                                                          | string   | optional |
| `cluster`         | The name of the cluster.                                                                                                                                               | string   | optional |
| `domain`          | The configured NATS domain of the server.                                                                                                                              | string   | optional |
"""

connect = md"""
| name            | description                                                                                                                                                                                                                                                                       | type   | required                     |
|-----------------|-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|--------|------------------------------|
| `verbose`       | Turns on [`+OK`](./#okerr) protocol acknowledgements.                                                                                                                                                                                                                             | bool   | true                         |
| `pedantic`      | Turns on additional strict format checking, e.g. for properly formed subjects.                                                                                                                                                                                                    | bool   | true                         |
| `tls_required`  | Indicates whether the client requires an SSL connection.                                                                                                                                                                                                                          | bool   | true                         |
| `auth_token`    | Client authorization token.                                                                                                                                                                                                                                                       | string | if `auth_required` is `true` |
| `user`          | Connection username.                                                                                                                                                                                                                                                              | string | if `auth_required` is `true` |
| `pass`          | Connection password.                                                                                                                                                                                                                                                              | string | if `auth_required` is `true` |
| `name`          | Client name.                                                                                                                                                                                                                                                                      | string | false                        |
| `lang`          | The implementation language of the client.                                                                                                                                                                                                                                        | string | true                         |
| `version`       | The version of the client.                                                                                                                                                                                                                                                        | string | true                         |
| `protocol`      | Sending `0` (or absent) indicates client supports original protocol. Sending `1` indicates that the client supports dynamic reconfiguration of cluster topology changes by asynchronously receiving [`INFO`](./#info) messages with known servers it can reconnect to.            | int    | false                        |
| `echo`          | If set to `false`, the server (version 1.2.0+) will not send originating messages from this connection to its own subscriptions. Clients should set this to `false` only for server supporting this feature, which is when `proto` in the `INFO` protocol is set to at least `1`. | bool   | false                        |
| `sig`           | In case the server has responded with a `nonce` on `INFO`, then a NATS client must use this field to reply with the signed `nonce`.                                                                                                                                               | string | if `nonce` received          |
| `jwt`           | The JWT that identifies a user permissions and account.                                                                                                                                                                                                                           | string | false                        |
| `no_responders` | Enable [quick replies for cases where a request is sent to a topic with no responders](/nats-concepts/core-nats/request-reply/reqreply.md#no-responders).                                                                                                                                           | bool   | false      |
| `headers`       | Whether the client supports headers.                                                                                                                                                                                                                                              | bool   | false                        |
| `nkey`          | The public NKey to authenticate the client. This will be used to verify the signature (`sig`) against the `nonce` provided in the `INFO` message.                                                                                                                                 | string | false                        |
"""

pub = md"""
| name       | description                                                                                   | type   | required |
|------------|-----------------------------------------------------------------------------------------------|--------|----------|
| `subject`  | The destination subject to publish to.                                                        | string | true     |
| `reply-to` | The reply subject that subscribers can use to send a response back to the publisher/requestor.| string | false    |
| `#bytes`   | The payload size in bytes.                                                                    | int    | true     |
| `payload`  | The message payload data.                                                                     | string | optional |
"""

hpub = md"""
| name            | description                                                                                     | type   | required |
|-----------------|-------------------------------------------------------------------------------------------------|--------|----------|
| `subject`       | The destination subject to publish to.                                                          | string | true     |
| `reply-to`      | The reply subject that subscribers can use to send a response back to the publisher/requestor.  | string | false    |
| `#header bytes` | The size of the headers section in bytes including the `␍␊␍␊` delimiter before the payload.     | int    | true     |
| `#total bytes`  | The total size of headers and payload sections in bytes.                                        | int    | true     |
| `headers`       | Header version `NATS/1.0␍␊` followed by one or more `name: value` pairs, each separated by `␍␊`.| string | false    |
| `payload`       | The message payload data.                                                                       | string | false    |
"""

sub = md"""
| name          | description                                                    | type   | required |
|---------------|----------------------------------------------------------------|--------|----------|
| `subject`     | The subject name to subscribe to.                              | string | true     |
| `queue group` | If specified, the subscriber will join this queue group.       | string | false    |
| `sid`         | A unique alphanumeric subscription ID, generated by the client.| string | true     |
"""

unsub = md"""
| name       | description                                                                | type   | required |
|------------|----------------------------------------------------------------------------|--------|----------|
| `sid`      | The unique alphanumeric subscription ID of the subject to unsubscribe from.| string | true     |
| `max_msgs` | A number of messages to wait for before automatically unsubscribing.       | int    | false    |
"""

msg = md"""
| name       | description                                                   | type   | presence |
|------------|---------------------------------------------------------------|--------|----------|
| `subject`  | Subject name this message was received on.                    | string | always   |
| `sid`      | The unique alphanumeric subscription ID of the subject.       | string | always   |
| `reply-to` | The subject on which the publisher is listening for responses.| string | optional |
| `#bytes`   | Size of the payload in bytes.                                 | int    | always   |
| `payload`  | The message payload data.                                     | string | optional |
"""

hmsg = md"""
| name            | description                                                                                     | type   | presence |
|-----------------|-------------------------------------------------------------------------------------------------|--------|----------|
| `subject`       | Subject name this message was received on.                                                      | string | always   |
| `sid`           | The unique alphanumeric subscription ID of the subject.                                         | string | always   |
| `reply-to`      | The subject on which the publisher is listening for responses.                                  | string | optional |
| `#header bytes` | The size of the headers section in bytes including the `␍␊␍␊` delimiter before the payload.     | int    | always   |
| `#total bytes`  | The total size of headers and payload sections in bytes.                                        | int    | always   |
| `headers`       | Header version `NATS/1.0␍␊` followed by one or more `name: value` pairs, each separated by `␍␊`.| string | optional |
| `payload`       | The message payload data.                                                                       | string | optional |
"""

docs = [info, connect, pub, hpub, sub, unsub, msg, hmsg]
structs = [:Info, :Connect, :Pub, :HPub, :Sub, :Unsub, :Msg, :HMsg]

open("../src/protocol_data.jl", "w") do f;
    println(f, "# This file is autogenerated. Maunal changes will be lost.")
    println(f)
    println(f, parse_operations(operations))
    println(f)
    println(f, "abstract type ProtocolMessage end")
    for struct_def in parse_markdown.(docs, structs)
        println(f)
        println(f, struct_def)
    end
end
