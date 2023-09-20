
const Message = Union{Msg, HMsg}

payload(::ProtocolMessage) = nothing
payload(msg::Msg) = msg.payload
payload(hmsg::HMsg) = hmsg.payload

needs_ack(msg::Union{Msg, HMsg}) = !isnothing(msg.reply_to) && startswith(msg.reply_to, "\$JS.ACK") # TODO: only HMsg?

argtype(handler) = first(methods(handler)).sig.parameters[2] # TODO: handle multi methods.

function find_msg_conversion_or_throw(T::Type)
    if T != Any && !hasmethod(Base.convert, (Type{T}, Msg))
        throw(MethodError(Base.convert, (T, Msg)))
    end
end