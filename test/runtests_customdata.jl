
using Test
using NATS

import Base: convert, show

struct Person
    name::String
    age::Int64
end

function convert(::Type{Person}, msg::NATS.Msg)
    name, age = split(payload(msg), ",")
    Person(name, parse(Int64, age))
end

function show(io::IO, ::NATS.MIME_PAYLOAD, person::Person)
    print(io, person.name)
    print(io, ",")
    print(io, person.age)
end

nc = NATS.connect()
sleep(5)
@assert nc.status == NATS.CONNECTED "Cannot establish connection, ensure NATS is working on $(NATS.NATS_HOST):$(NATS.NATS_PORT)."

nc = NATS.connect(default = true)

@testset "Publish subscribe with custom data" begin
    c = Channel()
    sub = subscribe("EMPLOYEES") do person::Person
        put!(c, person)
    end
    publish("EMPLOYEES", Person("Jacek", 33))
    result = take!(c)
    @test result isa Person
    @test result.name == "Jacek"
    @test result.age == 33
    @test length(nc.sub_channels) == 1
    unsubscribe(sub)
    sleep(0.1)
    @test length(nc.sub_channels) == 0
end

@testset "Request reply with custom data" begin
    sub = reply("EMPLOYEES.SUPERVISOR") do person::Person
        if person.name == "Jacek"
            Person("Zbigniew", 44), ["A" => "B"]
        else
            Person("Maciej", 55), ["A" => "B"]
        end
    end
    supervisor = request(Person, "EMPLOYEES.SUPERVISOR", Person("Jacek", 33))
    @test supervisor isa Person
    @test supervisor.name == "Zbigniew"
    @test supervisor.age == 44

    msg = request("EMPLOYEES.SUPERVISOR", Person("Anna", 33))
    @test msg isa NATS.Msg
end
