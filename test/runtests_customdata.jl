
using Test
using NATS

import Base: convert, show

struct Person
    name::String
    age::Int64
end

function convert(::Type{Person}, msg::Union{NATS.Msg, NATS.HMsg})
    name, age = split(payload(msg), ",")
    Person(name, parse(Int64, age))
end

function show(io::IO, ::NATS.MIME_PAYLOAD, person::Person)
    print(io, person.name)
    print(io, ",")
    print(io, person.age)
end

@testset "Publish subscribe with custom data" begin
    nc = NATS.connect()
    c = Channel()
    sub = subscribe(nc, "EMPLOYEES") do person::Person
        put!(c, person)
    end
    publish(nc, "EMPLOYEES", Person("Jacek", 33))
    result = take!(c)
    @test result isa Person
    @test result.name == "Jacek"
    @test result.age == 33
    @test length(nc.handlers) == 1
    unsubscribe(nc, sub)
    sleep(0.1)
    @test length(nc.handlers) == 0
end

@testset "Request reply with custom data" begin
    nc = NATS.connect()
    sub = reply(nc, "EMPLOYEES.SUPERVISOR") do person::Person
        if person.name == "Jacek"
            Person("Zbigniew", 44), ["A" => "B"]
        else
            Person("Maciej", 55), ["A" => "B"]
        end
    end
    supervisor = request(Person, nc, "EMPLOYEES.SUPERVISOR", Person("Jacek", 33))
    @test supervisor isa Person
    @test supervisor.name == "Zbigniew"
    @test supervisor.age == 44

    hmsg = request(nc, "EMPLOYEES.SUPERVISOR", Person("Anna", 33))
    @test hmsg isa NATS.HMsg
end
