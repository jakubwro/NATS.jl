### show.jl
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
# This file contains serialization utilities for converting structures into NATS protocol payload.
#
### Code:

import StructTypes: omitempties

# Before Julia 1.12 `unsafe_write` for `IOBuffer` copies data byte by byte, what is slow for
# large payloads. This is the same logic, but using `memcpy`.
@static if VERSION < v"1.12"
    function write_bytes(to::IOBuffer, p::Ptr{UInt8}, nb::UInt)
        Base.ensureroom(to, nb)
        ptr = (to.append ? to.size + 1 : to.ptr)
        written = Int(min(nb, Int(length(to.data))::Int - ptr + 1))
        data = to.data
        GC.@preserve data unsafe_copyto!(pointer(data, ptr), p, written)
        to.size = max(to.size, ptr + written - 1)
        if !to.append
            to.ptr += written
        end
        written
    end
else
    write_bytes(to::IOBuffer, p::Ptr{UInt8}, nb::UInt) = unsafe_write(to, p, nb)
end

write_bytes(io::IOBuffer, s::Union{String, SubString{String}}) = GC.@preserve s write_bytes(io, pointer(s), UInt(sizeof(s)))
write_bytes(io::IOBuffer, v::Vector{UInt8}) = GC.@preserve v write_bytes(io, pointer(v), UInt(length(v)))
write_bytes(io::IO, data) = write(io, data)

# Payload serialization.

function Base.show(io::IO, ::MIME_PAYLOAD, ::Nothing)
    # Empty payload, nothing to write.
    nothing
end

function Base.show(io::IO, ::MIME_PAYLOAD, ::Headers)
    # When only headers are provided, do not write any payload.
    # TODO: what if someone used Vector{Pair{String, String}} as payload?
    nothing
end

function Base.show(io::IO, ::MIME_PAYLOAD, payload::String)
    # Allows to return a string from the handler for `reply`.
    write_bytes(io, payload)
    nothing
end

function Base.show(io::IO, ::MIME_PAYLOAD, payload::JSON3.Object)
    # Allows to return JSON from the handler for `reply`.
    JSON3.write(io, payload)
    nothing
end

function Base.show(io::IO, mime::MIME_PAYLOAD, tup::Tuple{<:Any, Headers})
    # Allows to return a tuple from the handler, useful to override headers.
    Base.show(io, mime, first(tup))
    nothing
end

function Base.show(io::IO, mime::MIME_PAYLOAD, tup::Tuple{<:Any, Nothing})
    # Handle edge case when some method will return nothing headers, but still in a tuple with payload.
    Base.show(io, mime, first(tup))
    nothing
end

# Headers serialization.

function Base.show(io::IO, ::MIME_HEADERS, ::Any)
    # Default is empty header.
    nothing
end

function Base.show(io::IO, ::MIME_HEADERS, ::Nothing)
    # Empty headers, nothing to write.
    nothing
end

function Base.show(io::IO, mime::MIME_HEADERS, tup::Tuple{<:Any, Headers})
    Base.show(io, mime, last(tup))
    nothing
end

function Base.show(io::IO, ::MIME_HEADERS, s::String)
    # TODO: rethink this
    nothing
end

function Base.show(io::IO, ::MIME_HEADERS, headers::Headers)
    print(io, "NATS/1.0\r\n")
    for (key, value) in headers
        print(io, key)
        print(io, ": ")
        print(io, value)
        print(io, "\r\n")
    end
    print(io, "\r\n")
    nothing
end

# Protocol serialization.

StructTypes.omitempties(::Type{Connect}) = true

function show(io::IO, ::MIME_PROTOCOL, connect::Connect)
    write(io, "CONNECT $(JSON3.write(connect))\r\n")
end

function show(io::IO, ::MIME_PROTOCOL, pub::Pub)
    hbytes = pub.headers_length
    nbytes = length(pub.payload)
    if hbytes > 0
        write(io, "H")
    end
    write(io, "PUB ")
    write(io, pub.subject)
    if !isnothing(pub.reply_to) && !isempty(pub.reply_to)
        write(io, " ")
        write(io, pub.reply_to)
    end
    if hbytes > 0
        write(io, " $hbytes")
    end
    write(io, ' ')
    show(io, nbytes)
    # write(io, string(nbytes))
    write(io, "\r\n")
    write_bytes(io, pub.payload)
    write(io, "\r\n")
end

function show(io::IO, ::MIME_PROTOCOL, sub::Sub)
    queue_group = isnothing(sub.queue_group) ? "" : " $(sub.queue_group)"
    write(io, "SUB $(sub.subject)$queue_group $(sub.sid)\r\n")
end

function show(io::IO, ::MIME_PROTOCOL, unsub::Unsub)
    max_msgs = isnothing(unsub.max_msgs) ? "" : " $(unsub.max_msgs)"
    write(io, "UNSUB $(unsub.sid)$max_msgs\r\n")
end

function show(io::IO, ::MIME_PROTOCOL, unsub::Ping)
    write(io, "PING\r\n")
end

function show(io::IO, ::MIME_PROTOCOL, unsub::Pong)
    write(io, "PONG\r\n")
end

# Pretty print Msg.
function show(io::IO, mime::MIME"text/plain", msg::Msg)
    payload_limit = 500
    if msg.headers_length > 0
        write(io, "H")
    end
    write(io, "MSG $(msg.subject) $(msg.sid) ")
    if !(isnothing(msg.reply_to))
        write(io, "$(msg.reply_to) ")
    end
    if msg.headers_length > 0
        write(io, "$(msg.headers_length) ")
    end
    write(io, "$(length(msg.payload))\r\n")
    if length(msg.payload) > payload_limit
        write(io, String(first(msg.payload, payload_limit)))
        write(io, " ⋯ $(length(msg.payload) - payload_limit) bytes")
    else
        write(io, String(copy(msg.payload)))
    end
end
