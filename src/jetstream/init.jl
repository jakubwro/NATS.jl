
function jetstream_fallback_handler(nc::Connection, msg::Union{Msg, HMsg})
    needs_ack(msg) && nak(nc, msg)
end
