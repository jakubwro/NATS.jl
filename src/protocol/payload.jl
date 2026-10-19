### payload.jl
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
# This file contains utilities for NATS message payload manipulation.
#
### Code:

function payload(msg::Msg)
    data = msg.payload
    GC.@preserve data unsafe_string(pointer(data, firstindex(data) + msg.headers_length), max(0, length(data) - msg.headers_length))
end