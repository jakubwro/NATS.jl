### structs.jl
#
# Copyright (C) 2023 Jakub Wronowski.
#
# Maintainer: Jakub Wronowski <jakubwro@users.noreply.github.com>
# Keywords: nats, nats-client, julia
#
# This file is a part of NATS.jl.
#
# License is MIT.
#
### Commentary:
#
# This file contains data structures describing NATS protocol.
#
### Code:

abstract type ProtocolMessage end

"""
A client will need to start as a plain TCP connection, then when the server accepts a connection from the client, it will send information about itself, the configuration and security requirements necessary for the client to successfully authenticate with the server and exchange messages. When using the updated client protocol (see CONNECT below), INFO messages can be sent anytime by the server. This means clients with that protocol level need to be able to asynchronously handle INFO messages.

$(TYPEDFIELDS)
"""
struct Info <: ProtocolMessage
    "The unique identifier of the NATS server."
    server_id::String
    "The name of the NATS server."
    server_name::String
    "The version of NATS."
    version::String
    "The version of golang the NATS server was built with."
    go::String
    "The IP address used to start the NATS server, by default this will be `0.0.0.0` and can be configured with `-client_advertise host:port`."
    host::String
    "The port number the NATS server is configured to listen on."
    port::Int
    "Whether the server supports headers."
    headers::Bool
    "Maximum payload size, in bytes, that the server will accept from the client."
    max_payload::Int
    "An integer indicating the protocol version of the server. The server version 1.2.0 sets this to `1` to indicate that it supports the \"Echo\" feature."
    proto::Int
    "The internal client identifier in the server. This can be used to filter client connections in monitoring, correlate with error logs, etc..."
    client_id::Union{UInt64, Nothing}
    "If this is true, then the client should try to authenticate upon connect."
    auth_required::Union{Bool, Nothing}
    "If this is true, then the client must perform the TLS/1.2 handshake. Note, this used to be `ssl_required` and has been updated along with the protocol from SSL to TLS."
    tls_required::Union{Bool, Nothing}
    "If this is true, the client must provide a valid certificate during the TLS handshake."
    tls_verify::Union{Bool, Nothing}
    "If this is true, the client can provide a valid certificate during the TLS handshake."
    tls_available::Union{Bool, Nothing}
    "List of server urls that a client can connect to."
    connect_urls::Union{Vector{String}, Nothing}
    "List of server urls that a websocket client can connect to."
    ws_connect_urls::Union{Vector{String}, Nothing}
    "If the server supports *Lame Duck Mode* notifications, and the current server has transitioned to lame duck, `ldm` will be set to `true`."
    ldm::Union{Bool, Nothing}
    "The git hash at which the NATS server was built."
    git_commit::Union{String, Nothing}
    "Whether the server supports JetStream."
    jetstream::Union{Bool, Nothing}
    "The IP of the server."
    ip::Union{String, Nothing}
    "The IP of the client."
    client_ip::Union{String, Nothing}
    "The nonce for use in CONNECT."
    nonce::Union{String, Nothing}
    "The name of the cluster."
    cluster::Union{String, Nothing}
    "The configured NATS domain of the server."
    domain::Union{String, Nothing}
end

"""
The CONNECT message is the client version of the `INFO` message. Once the client has established a TCP/IP socket connection with the NATS server, and an `INFO` message has been received from the server, the client may send a `CONNECT` message to the NATS server to provide more information about the current connection as well as security information.

$(TYPEDFIELDS)
"""
struct Connect <: ProtocolMessage
    # TODO: restore link #NATS.Ok
    "Turns on `+OK` protocol acknowledgements."
    verbose::Bool
    "Turns on additional strict format checking, e.g. for properly formed subjects."
    pedantic::Bool
    "Indicates whether the client requires SSL connection."
    tls_required::Bool
    "Client authorization token."
    auth_token::Union{String, Nothing}
    "Connection username."
    user::Union{String, Nothing}
    "Connection password."
    pass::Union{String, Nothing}
    "Client name."
    name::Union{String, Nothing}
    "The implementation language of the client."
    lang::String
    "The version of the client."
    version::String
    # TODO: restore link ./#NATS.Info
    "Sending `0` (or absent) indicates client supports original protocol. Sending `1` indicates that the client supports dynamic reconfiguration of cluster topology changes by asynchronously receiving `INFO` messages with known servers it can reconnect to."
    protocol::Union{Int, Nothing}
    "If set to `false`, the server (version 1.2.0+) will not send originating messages from this connection to its own subscriptions. Clients should set this to `false` only for server supporting this feature, which is when `proto` in the `INFO` protocol is set to at least `1`."
    echo::Union{Bool, Nothing}
    "In case the server has responded with a `nonce` on `INFO`, then a NATS client must use this field to reply with the signed `nonce`."
    sig::Union{String, Nothing}
    "The JWT that identifies a user permissions and account."
    jwt::Union{String, Nothing}
    "Enable quick replies for cases where a request is sent to a topic with no responders."
    no_responders::Union{Bool, Nothing}
    "Whether the client supports headers."
    headers::Union{Bool, Nothing}
    "The public NKey to authenticate the client. This will be used to verify the signature (`sig`) against the `nonce` provided in the `INFO` message."
    nkey::Union{String, Nothing}
end

"""
The PUB message publishes the message payload to the given subject name, optionally supplying a reply subject. If a reply subject is supplied, it will be delivered to eligible subscribers along with the supplied payload. Note that the payload itself is optional. To omit the payload, set the payload size to 0, but the second CRLF is still required.

The HPUB message is the same as PUB but extends the message payload to include NATS headers. Note that the payload itself is optional. To omit the payload, set the total message size equal to the size of the headers. Note that the trailing CR+LF is still required.

$(TYPEDFIELDS)
"""
struct Pub <: ProtocolMessage
    "The destination subject to publish to."
    subject::String
    "The reply subject that subscribers can use to send a response back to the publisher/requestor."
    reply_to::Union{String, Nothing}
    "Length of headers data inside payload"
    headers_length::Int64
    "Optional headers (`NATS/1.0␍␊` followed by one or more `name: value` pairs, each separated by `␍␊`) followed by payload data."
    payload::Vector{UInt8}
end

"""
`SUB` initiates a subscription to a subject, optionally joining a distributed queue group.

$(TYPEDFIELDS)
"""
struct Sub <: ProtocolMessage
    "The subject name to subscribe to."
    subject::String
    "If specified, the subscriber will join this queue group."
    queue_group::Union{String, Nothing}
    "A unique alphanumeric subscription ID, generated by the client."
    sid::String
end

"""
`UNSUB` unsubscribes the connection from the specified subject, or auto-unsubscribes after the specified number of messages has been received.

$(TYPEDFIELDS)
"""
struct Unsub <: ProtocolMessage
    "The unique alphanumeric subscription ID of the subject to unsubscribe from."
    sid::String
    "A number of messages to wait for before automatically unsubscribing."
    max_msgs::Union{Int, Nothing}
end

"""
The `MSG` protocol message is used to deliver an application message to the client.

The HMSG message is the same as MSG, but extends the message payload with headers. See also [ADR-4 NATS Message Headers](https://github.com/nats-io/nats-architecture-and-design/blob/main/adr/ADR-4.md).

$(TYPEDFIELDS)
"""
struct Msg <: ProtocolMessage
    "Subject name this message was received on."
    subject::String
    "The unique alphanumeric subscription ID of the subject."
    sid::String
    "The subject on which the publisher is listening for responses."
    reply_to::Union{String, Nothing}
    "Length of headers data inside payload"
    headers_length::Int64
    "Optional headers (`NATS/1.0␍␊` followed by one or more `name: value` pairs, each separated by `␍␊`) followed by payload data."
    payload::AbstractVector{UInt8}
end

"""
`PING` and `PONG` implement a simple keep-alive mechanism between client and server.

$(TYPEDFIELDS)
"""
struct Ping <: ProtocolMessage
end

"""
`PING` and `PONG` implement a simple keep-alive mechanism between client and server.

$(TYPEDFIELDS)
"""
struct Pong <: ProtocolMessage
end

"""
The `-ERR` message is used by the server indicate a protocol, authorization, or other runtime connection error to the client. Most of these errors result in the server closing the connection.

$(TYPEDFIELDS)
"""
struct Err <: ProtocolMessage
    "Error message."
    message::String
end

"""
When the `verbose` connection option is set to `true` (the default value), the server acknowledges each well-formed protocol message from the client with a `+OK` message.

$(TYPEDFIELDS)
"""
struct Ok <: ProtocolMessage
end

# This allows structural equality on protocol messages with `==` and `isequal` functions.
function Base.:(==)(a::M, b::M) where {M <: ProtocolMessage}
    all(field -> getfield(a, field) == getfield(b, field), fieldnames(M))
end