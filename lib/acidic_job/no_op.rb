# frozen_string_literal: true

# Represents an action to perform a no-op. One possible option for a return
# from an #atomic_phase block.
module AcidicJob
  class NoOp
    def call(_key)
      # no-op
    end
  end
end
