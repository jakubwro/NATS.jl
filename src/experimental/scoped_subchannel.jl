
const ssubchannel = ScopedValue{Channel}()

function scoped_subchannel()
    ch = ScopedValues.get(ssubchannel)
    if isnothing(ch)
        error("""No scoped subscription channel""")
    end
    ch.value
end

function with_subchannel(f, ch::Channel)
    with(f, ssubchannel => ch)
end
