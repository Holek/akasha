describe Akasha::Storage::HttpEventStore, integration: true do
  subject { described_class.new(http_es_config) }

  describe '#streams' do
    it 'returns a new stream for different stream names' do
      expect(subject.streams[:foo]).to_not be(subject.streams[:bar])
    end
  end

  describe '#merge_all_by_event' do
    let(:projection_name) { gensym(:projection) }
    let(:stream_name) { gensym(:stream) }
    let(:world_created) { Akasha::Event.new(gensym(:world_created)) }
    let(:ruby_invented) { Akasha::Event.new(gensym(:ruby_invented)) }
    let(:world_ended) { Akasha::Event.new(gensym(:world_ended)) }
    let(:events) do
      [
        world_created,
        ruby_invented,
        world_ended
      ]
    end
    let(:poll_seconds) { 1 }

    it 'creates stream containing events with matching names' do
      subject.merge_all_by_event(into: projection_name, only: [world_created.name, world_ended.name])
      subject.streams[stream_name].write_events(events)

      wait(10).for do
        subject.streams[projection_name].read_events(0, 999, poll_seconds).map(&:name).uniq
      end.to match_array([world_created.name, world_ended.name])
    end

    it 'supports changing the list of names' do
      subject.merge_all_by_event(into: projection_name, only: [world_created.name, world_ended.name])
      subject.streams[projection_name].read_events(0, 999, poll_seconds)
      subject.merge_all_by_event(into: projection_name, only: [world_created.name])
      subject.streams[stream_name].write_events(events)

      wait(10).for do
        subject.streams[projection_name].read_events(0, 999, poll_seconds).map(&:name).uniq
      end.to match_array([world_created.name])
    end
  end
end
