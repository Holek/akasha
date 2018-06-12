module Akasha
  # Base class for routing events to event listeners.
  class EventRouterBase
    def initialize
      @routes = Hash.new { |hash, key| hash[key] = [] }
    end

    # Registers a new event listener, derived from
    # `Akasha::EventListener`.
    def register_event_listener(event_name, listener)
      if listener.is_a?(Class)
        @routes[event_name] << listener.new
      else
        @routes[event_name] << listener
      end
    end

    # Routes an event.
    def route(event_name, aggregate_id, **data)
      @routes[event_name].each do |listener|
        begin
          listener.public_send(:"on_#{event_name}", aggregate_id, **data)
        rescue RuntimeError => e
          log "Error handling event #{event_name.inspect}: #{e}"
        end
      end
    end

    protected

    def registered_event_names
      @routes.keys
    end

    private

    def log(msg)
      puts msg # rubocop:disable Rails/Output
    end
  end
end
