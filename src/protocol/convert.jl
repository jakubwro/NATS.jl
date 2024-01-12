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

function convert(::Type{String}, msg::NATS.Msg)
    # Default representation on msg content is payload string.
    # This allows to use handlers that take just a payload string and do not use other fields.
    payload(msg)
end
