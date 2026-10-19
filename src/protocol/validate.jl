### validate.jl
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
# This file contains implementation of functions for the validation of protocol messages.
#
### Code:

function validate(pub::Pub)
    # Checked on bytes, it is called for each publication, ASCII characters cannot be a part of a multibyte UTF-8 character.
    subject = codeunits(pub.subject)
    isempty(subject) && error("Publication subject is empty")
    first(subject) == UInt8('.') && error("Publication subject '$(pub.subject)' cannot start with '.'")
    last(subject) == UInt8('.') && error("Publication subject '$(pub.subject)' cannot end with '.'")
    UInt8(' ') in subject && error("Publication subject contains invalid character ' '.")
    true
end
