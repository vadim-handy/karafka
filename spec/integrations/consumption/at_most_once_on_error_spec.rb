# frozen_string_literal: true

# When marking as consumed before the error, message should be skipped as it should be considered
# consumed

setup_karafka(allow_errors: true)

SuperException = Class.new(Exception)

class Consumer < Karafka::BaseConsumer
  def consume
    messages.each do |message|
      mark_as_consumed(message)

      raise if message.offset == 5

      DT[:offsets] << message.offset
    end
  end
end

draw_routes(Consumer)

produce_many(DT.topic, DT.uuids(10))

start_karafka_and_wait_until do
  DT[:offsets].count >= 9
end

assert !DT[:offsets].include?(5)
