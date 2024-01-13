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
# This file contains implementation of functions for validation of protocol messages.
#
### Code:

function validate(pub::Pub)
    isempty(pub.subject) && error("Publication subject is empty")
    startswith(pub.subject, '.') && error("Publication subject '$(pub.subject)' cannot start with '.'")
    endswith(pub.subject, '.') && error("Publication subject '$(pub.subject)' cannot end with '.'")
    for c in pub.subject
        if c == ' '
            error("Publication subject contains invalid character '$c'.")
        end
    end
    true
end
