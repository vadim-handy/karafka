# frozen_string_literal: true

# This Karafka component is a Pro component under a commercial license.
# This Karafka component is NOT licensed under LGPL.
#
# All of the commercial components are present in the lib/karafka/pro directory of this
# repository and their usage requires commercial license agreement.
#
# Karafka has also commercial-friendly license, commercial support and commercial components.
#
# By sending a pull request to the pro components, you are agreeing to transfer the copyright of
# your code to Maciej Mensfeld.

module Karafka
  module Pro
    module Processing
      module Strategies
        module Aj
          # ActiveJob enabled
          # Long-Running Job enabled
          # Manual offset management enabled
          # Virtual Partitions enabled
          module LrjMomVp
            include Strategies::Default
            include Strategies::Vp::Default

            # Features for this strategy
            FEATURES = %i[
              active_job
              long_running_job
              manual_offset_management
              virtual_partitions
            ].freeze

            # No actions needed for the standard flow here
            def handle_before_enqueue
              super

              coordinator.on_enqueued do
                pause(coordinator.seek_offset, Strategies::Lrj::Default::MAX_PAUSE_TIME, false)
              end
            end

            # Standard flow without any features
            def handle_after_consume
              coordinator.on_finished do |last_group_message|
                if coordinator.success?
                  coordinator.pause_tracker.reset

                  mark_as_consumed(last_group_message) unless revoked?
                  seek(coordinator.seek_offset) unless revoked?

                  resume
                else
                  # If processing failed, we need to pause
                  # For long running job this will overwrite the default never-ending pause and
                  # will cause the processing to keep going after the error backoff
                  retry_after_pause
                end
              end
            end

            # LRJ cannot resume here. Only in handling the after consumption
            def handle_revoked
              coordinator.on_revoked do
                coordinator.revoke
              end

              Karafka.monitor.instrument('consumer.revoke', caller: self)
              Karafka.monitor.instrument('consumer.revoked', caller: self) do
                revoked
              end
            end
          end
        end
      end
    end
  end
end
