require 'base64'
require 'corefines/hash'
require 'json'
require 'faraday'
require 'faraday_middleware'
require 'rack/utils'
require 'retries'
require 'time'
require 'typhoeus/adapters/faraday'

require_relative 'event_serializer'
require_relative 'response_handler'
require_relative 'projection_manager'

module Akasha
  module Storage
    class HttpEventStore
      # Eventstore HTTP client.
      class Client
        using Corefines::Hash

        # A lower limit for a retry interval.
        MIN_RETRY_INTERVAL = 0
        # An upper limit for a retry interval.
        MAX_RETRY_INTERVAL = 10.0

        # Creates a new client for the host and port with optional username and password
        # for authenticating certain requests.
        def initialize(host: 'localhost', port: 2113, username: nil, password: nil)
          @username = username
          @password = password
          @conn = connection(host, port)
          @serializer = EventSerializer.new
        end

        # Append events to stream, idempotently retrying_on_network_failures up to `max_retries`
        def retry_append_to_stream(stream_name, events, expected_version = nil, max_retries: 0)
          retrying_on_network_failures(max_retries) do
            append_to_stream(stream_name, events, expected_version)
          end
        end

        # Read events from stream, retrying_on_network_failures up to `max_retries` in case of network failures.
        # Reads `count` events starting from `start` inclusive.
        # Can long-poll for events if `poll` is specified.`
        def retry_read_events_forward(stream_name, start, count, poll = 0, max_retries: 0)
          retrying_on_network_failures(max_retries) do
            safe_read_events(stream_name, start, count, poll)
          end
        end

        # Merges all streams into one, filtering the resulting stream
        # so it only contains events with the specified names, using
        # a projection.
        #
        # Arguments:
        #   `name` - name of the projection stream
        #   `event_names` - array of event names
        def merge_all_by_event(name, event_names, max_retries: 0)
          retrying_on_network_failures(max_retries) do
            ProjectionManager.new(self).merge_all_by_event(name, event_names)
          end
        end

        # Reads stream metadata.
        def retry_read_metadata(stream_name, max_retries: 0)
          retrying_on_network_failures(max_retries) do
            safe_read_metadata(stream_name)
          end
        end

        # Updates stream metadata.
        def retry_write_metadata(stream_name, metadata)
          event = Akasha::Event.new(:stream_metadata_changed, SecureRandom.uuid, metadata)
          retry_append_to_stream("#{stream_name}/metadata", [event])
        end

        # Issues a generic request against the API.
        def request(method, path, body = nil, headers = {})
          body = @conn.public_send(method, path, body, auth_headers.merge(headers)).body
          return {} if body.empty?
          body
        end

        private

        def connection(host, port)
          Faraday.new do |conn|
            conn.host = host
            conn.port = port
            conn.response :json, content_type: 'application/json'
            conn.use ResponseHandler
            conn.adapter :typhoeus
          end
        end

        def auth_headers
          if @username && @password
            auth = Base64.urlsafe_encode64([@username, @password].join(':'))
            {
              'Authorization' => "Basic #{auth}"
            }
          else
            {}
          end
        end

        def retrying_on_network_failures(max_retries)
          with_retries(base_sleep_seconds: MIN_RETRY_INTERVAL,
                       max_sleep_seconds: MAX_RETRY_INTERVAL,
                       max_tries: 1 + max_retries,
                       rescue: [Faraday::TimeoutError, Faraday::ConnectionFailed]) do
            yield
          end
        end

        def append_to_stream(stream_name, events, _expected_version = nil)
          @conn.post("/streams/#{stream_name}") do |req|
            req.headers = {
              'Content-Type' => 'application/vnd.eventstore.events+json',
              # 'ES-ExpectedVersion' => expected_version
            }
            req.body = to_event_data(events).to_json
          end
        end

        def safe_read_events(stream_name, start, count, poll)
          resp = @conn.get("/streams/#{stream_name}/#{start}/forward/#{count}") do |req|
            req.headers = {
              'Accept' => 'application/json'
            }
            req.headers['ES-LongPoll'] = poll if poll&.positive?
            req.params['embed'] = 'body'
          end
          event_data = resp.body['entries']
          to_events(event_data)
        rescue HttpClientError => e
          return [] if e.status_code == 404
          raise
        rescue URI::InvalidURIError
          raise InvalidStreamNameError, "Invalid stream name: #{stream_name}"
        end

        def safe_read_metadata(stream_name)
          metadata = request(:get, "/streams/#{stream_name}/metadata", nil, 'Accept' => 'application/json')
          metadata.symbolize_keys
        rescue HttpClientError => e
          return {} if e.status_code == 404
          raise
        rescue URI::InvalidURIError
          raise InvalidStreamNameError, "Invalid stream name: #{stream_name}"
        end

        def to_event_data(events)
          @serializer.serialize(events)
        end

        def to_events(es_events)
          es_events = es_events.map do |ev|
            ev['data'] &&= JSON.parse(ev['data'])
            ev['metaData'] &&= JSON.parse(ev['metaData'])
            ev
          end
          @serializer.deserialize(es_events)
        end
      end
    end
  end
end
