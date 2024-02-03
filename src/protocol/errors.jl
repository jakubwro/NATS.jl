### errors.jl
#
# Copyright (C) 2024 Jakub Wronowski.
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
# This file contains implementations for handling NATS protocol errors.
#
### Code:

struct NATSError <: Exception
    code::Int64
    message::String
end

function has_error_status(code::Int64)
    code in 400:599
end

function has_error_status(msg::NATS.Msg)
    has_error_status(statuscode(msg))
end

function throw_on_error_status(msg::Msg)
    msg_status, status_message = statusinfo(msg)
    if has_error_status(msg_status)
        throw(NATSError(msg_status, status_message))
    end
    msg
end
