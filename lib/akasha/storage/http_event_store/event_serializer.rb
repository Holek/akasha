require 'corefines/hash'

module Akasha
  module Storage
    class HttpEventStore
      # Serializes and deserializes events to and from the format required
      # by the HTTP Eventstore API
      class EventSerializer
        using Corefines::Hash

        def serialize(events)
          events.map do |event|
            base = {
              'eventType' => event.name,
              'data' => event.data,
              'metaData' => event.metadata.to_hash
            }
            base['eventId'] = event.id unless event.id.nil?
            base
          end
        end

        def deserialize(es_events)
          es_events.map do |ev|
            metadata = ev['metaData']&.symbolize_keys || {}
            data = ev['data']&.symbolize_keys || {}
            event = Akasha::Event.new(ev['eventType'].to_sym, ev['eventId'], OpenStruct.new(metadata), **data)
            event
          end
        end
      end
    end
  end
end
