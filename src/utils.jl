
payload(::ProtocolMessage) = nothing
payload(msg::Msg) = msg.payload
payload(hmsg::HMsg) = hmsg.payload

needs_ack(msg::Union{Msg, HMsg}) = !isnothing(msg.reply_to) && startswith(msg.reply_to, "\$JS.ACK") # TODO: only HMsg?
