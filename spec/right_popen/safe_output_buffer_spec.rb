require ::File.expand_path(::File.join(::File.dirname(__FILE__), '..', 'spec_helper'))
require ::File.expand_path(::File.join(::File.dirname(__FILE__), '..', '..', 'lib', 'right_popen', 'safe_output_buffer'))

describe RightScale::RightPopen::SafeOutputBuffer do

  context 'given a default buffer' do
    subject { described_class.new }

    it 'should limit line count and length' do
      (described_class::DEFAULT_MAX_LINE_COUNT * 2).times do |line_index|
        data = 'x' * rand(described_class::DEFAULT_MAX_LINE_LENGTH * 3)
        subject.safe_buffer_data(data).should be_true
      end
      subject.buffer.size.should == described_class::DEFAULT_MAX_LINE_COUNT
      subject.buffer.first.should == described_class::ELLIPSIS
      subject.buffer.last.should_not == described_class::ELLIPSIS
      subject.buffer.each do |line|
        (line.length <= described_class::DEFAULT_MAX_LINE_LENGTH).should be_true
      end
      text = subject.display_text
      text.should_not be_empty
      text.lines.count.should == subject.buffer.size
    end
  end

end
