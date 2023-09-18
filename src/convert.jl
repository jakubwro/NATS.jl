function convert(::Type{String}, msg::Union{NATS.Msg, NATS.HMsg})
    payload(msg)
end

function convert(::Type{Any}, msg::Union{NATS.Msg, NATS.HMsg})
    # This is needed to make type unannotated callback handlers work.
    msg
end
