### convert.jl
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
# This file contains deserialization utilities for converting NATS protocol messages into structured data.
#
### Code:

bytes_string(buffer::Vector{UInt8}, range::UnitRange{Int64}) = GC.@preserve buffer unsafe_string(pointer(buffer, first(range)), length(range))

convert(::Type{Msg}, msgraw::NATS.MsgRaw) = convert_msg(msgraw, "")

# Converts reusing `subject` if it is equal to the message subject. It avoids allocation for each message
# when subsequent messages have the same subject, what is typical for a subscription.
function convert_msg(msgraw::NATS.MsgRaw, subject::String)::Msg
    buffer = msgraw.buffer
    subject_range = msgraw.subject_range
    is_same_subject = sizeof(subject) == length(subject_range) && GC.@preserve buffer subject begin
        0 == ccall(:memcmp, Cint, (Ptr{UInt8}, Ptr{UInt8}, Csize_t), pointer(buffer, first(subject_range)), pointer(subject), sizeof(subject))
    end
    if !is_same_subject
        subject = bytes_string(buffer, subject_range)
    end
    reply_to = isempty(msgraw.reply_to_range) ? nothing : bytes_string(buffer, msgraw.reply_to_range)
    payload = view(buffer, msgraw.payload_range)
    Msg(subject, msgraw.sid, reply_to, msgraw.header_bytes, payload)
end

function convert(::Type{String}, msg::NATS.Msg)
    # The default representation of msg content is the payload string.
    # This allows to use handlers that take just a payload string and do not use other fields.
    payload(msg)
end

function convert(::Type{JSON3.Object}, msg::NATS.Msg)
    # TODO: some validation if the header has error headers
    JSON3.read(@view msg.payload[(begin + msg.headers_length):end])
end

function convert(::Type{Tuple{String, NATS.Headers}}, msg::NATS.Msg)
    # TODO: some validation if the header has error headers
    payload(msg), headers(msg)
end
