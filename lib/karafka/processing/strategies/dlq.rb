# frozen_string_literal: true

module Karafka
  module Processing
    module Strategies
      # When using dead letter queue, processing won't stop after defined number of retries
      # upon encountering non-critical errors but the messages that error will be moved to a
      # separate topic with their payload and metadata, so they can be handled differently.
      module Dlq
        include Default

        # Apply strategy when only dead letter queue is turned on
        FEATURES = %i[
          dead_letter_queue
        ].freeze

        # When manual offset management is on, we do not mark anything as consumed automatically
        # and we rely on the user to figure things out
        def handle_after_consume
          return if revoked?

          if coordinator.success?
            coordinator.pause_tracker.reset

            return if coordinator.manual_pause?

            mark_as_consumed(messages.last)
          elsif coordinator.pause_tracker.attempt <= topic.dead_letter_queue.max_retries
            retry_after_pause
          # If we've reached number of retries that we could, we need to skip the first message
          # that was not marked as consumed, pause and continue, while also moving this message
          # to the dead topic
          else
            # We reset the pause to indicate we will now consider it as "ok".
            coordinator.pause_tracker.reset

            skippable_message, = find_skippable_message

            # Send skippable message to the dql topic
            dispatch_to_dlq(skippable_message)

            # We mark the broken message as consumed and move on
            mark_as_consumed(skippable_message)

            return if revoked?

            # We pause to backoff once just in case.
            pause(coordinator.seek_offset, nil, false)
          end
        end

        # Finds the message may want to skip (all, starting from first)
        # @private
        # @return [Array<Karafka::Messages::Message, Boolean>] message we may want to skip and
        #   information if this message was from marked offset or figured out via mom flow
        def find_skippable_message
          skippable_message = messages.find do |msg|
            coordinator.marked? && msg.offset == coordinator.seek_offset
          end

          # If we don't have the message matching the last comitted offset, it means that
          # user operates with manual offsets and we're beyond the batch in which things
          # broke for the first time. Then we skip the first (as no markings) and we
          # move on one by one.
          skippable_message ? [skippable_message, true] : [messages.first, false]
        end

        # Moves the broken message into a separate queue defined via the settings
        # @private
        # @param skippable_message [Karafka::Messages::Message] message we are skipping that also
        #   should go to the dlq topic
        def dispatch_to_dlq(skippable_message)
          producer.produce_async(
            topic: topic.dead_letter_queue.topic,
            payload: skippable_message.raw_payload
          )

          # Notify about dispatch on the events bus
          Karafka.monitor.instrument(
            'dead_letter_queue.dispatched',
            caller: self,
            message: skippable_message
          )
        end
      end
    end
  end
end
