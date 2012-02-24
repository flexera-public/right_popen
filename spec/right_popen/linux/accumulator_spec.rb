#--  -*- mode: ruby; encoding: utf-8 -*-
# Copyright: Copyright (c) 2011 RightScale, Inc.
#
# Permission is hereby granted, free of charge, to any person obtaining
# a copy of this software and associated documentation files (the
# 'Software'), to deal in the Software without restriction, including
# without limitation the rights to use, copy, modify, merge, publish,
# distribute, sublicense, and/or sell copies of the Software, and to
# permit persons to whom the Software is furnished to do so, subject to
# the following conditions:
#
# The above copyright notice and this permission notice shall be
# included in all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED 'AS IS', WITHOUT WARRANTY OF ANY KIND,
# EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
# MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
# IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
# CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
# TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
# SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
#++

require File.expand_path(File.join(File.dirname(__FILE__), '..', '..', 'spec_helper'))

module RightScale::RightPopen
  describe Accumulator do
    before(:each) do
      @process = flexmock("process")
      @process.should_receive(:pid).and_return(42)
    end

    describe "#tick" do
      context 'with a live child' do
        before(:each) do
          @process.should_receive(:status).and_return(nil)
          @process.should_receive(:status=)
          @input = flexmock("input")
          @output = flexmock("output")
          @read = flexmock("read")
          @write = flexmock("write")
        end
        
        it 'should skip calling select if no pipes are given' do
          a = Accumulator.new(@process, [], [], [], [])
          flexmock(::Process).should_receive(:waitpid2).with(42, ::Process::WNOHANG).once.and_return(nil)
          a.tick.should be_false
        end

        it 'should just check waitpid if the select times out' do
          a = Accumulator.new(@process, [@input], [@read], [@output], [@write])
          flexmock(::IO).should_receive(:select).with([@input], [@output], nil, 0.1).once.and_return([[], [], []])
          flexmock(::Process).should_receive(:waitpid2).with(42, ::Process::WNOHANG).once.and_return(nil)
          a.tick.should be_false
        end

        it 'should use the timeout value in the select' do
          value = flexmock("value")
          a = Accumulator.new(@process, [@input], [@read], [@output], [@write])
          flexmock(::IO).should_receive(:select).with([@input], [@output], nil, value).once.and_return([[], [], []])
          flexmock(::Process).should_receive(:waitpid2).with(42, ::Process::WNOHANG).once.and_return(nil)
          a.tick(value).should be_false
        end

        it 'should retry the select when seeing Errno::EAGAIN or Errno::EINTR' do
          a = Accumulator.new(@process, [@input], [@read], [@output], [@write])
          flexmock(::IO).should_receive(:select).with([@input], [@output], nil, 0.1).times(3).and_raise(Errno::EAGAIN).and_raise(Errno::EINTR).and_return([[], [], []])
          flexmock(::Process).should_receive(:waitpid2).with(42, ::Process::WNOHANG).once.and_return(nil)
          a.tick.should be_false
        end

        it 'should read data from the pipe and call the reader if it is ready' do
          value = flexmock("value")
          a = Accumulator.new(@process, [@input], [@read], [@output], [@write])
          flexmock(::IO).should_receive(:select).with([@input], [@output], nil, 0.1).once.and_return([[@input], [], []])
          @input.should_receive(:eof?).once.and_return(false)
          @input.should_receive(:readpartial).with(Accumulator::READ_CHUNK_SIZE).once.and_return(value)
          @read.should_receive(:call).with(value).once
          flexmock(::Process).should_receive(:waitpid2).with(42, ::Process::WNOHANG).once.and_return(nil)
          a.tick.should be_false
        end

        it 'should read data from the pipe and throw it away if no reader' do
          value = flexmock("value")
          a = Accumulator.new(@process, [@input], [], [@output], [@write])
          flexmock(::IO).should_receive(:select).with([@input], [@output], nil, 0.1).once.and_return([[@input], [], []])
          @input.should_receive(:eof?).once.and_return(false)
          @input.should_receive(:readpartial).with(Accumulator::READ_CHUNK_SIZE).once.and_return(value)
          flexmock(::Process).should_receive(:waitpid2).with(42, ::Process::WNOHANG).once.and_return(nil)
          a.tick.should be_false
        end

        it 'should call the writer and then write data to the pipe if it is ready' do
          value = flexmock("value")
          a = Accumulator.new(@process, [@input], [@read], [@output], [@write])
          flexmock(::IO).should_receive(:select).with([@input], [@output], nil, 0.1).once.and_return([[], [@output], []])
          @write.should_receive(:call).with().once.and_return(value)
          value.should_receive(:[]).with(30..-1).and_return("")
          value.should_receive("empty?").and_return(false)
          @output.should_receive(:write_nonblock).with(value).once.and_return(30)
          flexmock(::Process).should_receive(:waitpid2).with(42, ::Process::WNOHANG).once.and_return(nil)
          a.tick.should be_false
        end

        it 'should only call the writer when it is stalling' do
          value = flexmock("value")
          other = flexmock("other value")
          a = Accumulator.new(@process, [@input], [@read], [@output], [@write])
          flexmock(::IO).should_receive(:select).with([@input], [@output], nil, 0.1).and_return([[], [@output], []])
          @write.should_receive(:call).with().once.and_return(value)
          value.should_receive(:[]).with(30..-1).and_return(other)
          other.should_receive(:[]).with(20..-1).and_return("")
          value.should_receive("empty?").and_return(false)
          other.should_receive("empty?").and_return(false)
          @output.should_receive(:write_nonblock).with(value).once.and_return(30)
          @output.should_receive(:write_nonblock).with(other).once.and_return(20)
          flexmock(::Process).should_receive(:waitpid2).with(42, ::Process::WNOHANG).and_return(nil)
          a.tick.should be_false
          a.tick.should be_false
        end

        it 'should not read data from the pipe any more if EOF has been reached' do
          value = flexmock("value")
          a = Accumulator.new(@process, [@input], [@read], [], [])
          flexmock(::IO).should_receive(:select).with([@input], [], nil, 0.1).once.and_return([[@input], [], []])
          @input.should_receive(:eof?).once.and_return(true)
          @input.should_receive(:close).once
          flexmock(::Process).should_receive(:waitpid2).with(42, ::Process::WNOHANG).twice.and_return(nil)
          a.tick.should be_false
          a.tick.should be_false
        end

        it 'should not write data to the pipe any more if the caller has no more data' do
          value = flexmock("value")
          a = Accumulator.new(@process, [], [], [@output], [@write])
          flexmock(::IO).should_receive(:select).with([], [@output], nil, 0.1).once.and_return([[], [@output], []])
          @write.should_receive(:call).once.and_return(nil)
          @output.should_receive(:close).once
          flexmock(::Process).should_receive(:waitpid2).with(42, ::Process::WNOHANG).twice.and_return(nil)
          a.tick.should be_false
          a.tick.should be_false
        end

        it 'should not write data to the pipe any more if the caller is nil' do
          a = Accumulator.new(@process, [], [], [@output], [nil])
          flexmock(::IO).should_receive(:select).with([], [@output], nil, 0.1).once.and_return([[], [@output], []])
          @output.should_receive(:close).once
          flexmock(::Process).should_receive(:waitpid2).with(42, ::Process::WNOHANG).twice.and_return(nil)
          a.tick.should be_false
          a.tick.should be_false
        end
      end

      it 'should update the status if waitpid is successful' do
        a = Accumulator.new(@process, [], [], [], [])
        status = flexmock("status")
        flexmock(::Process).should_receive(:waitpid2).with(42, ::Process::WNOHANG).once.and_return(status)
        @process.should_receive(:status).twice.and_return(nil).and_return(status)
        @process.should_receive(:status=).with(status).once
        a.tick.should be_true
      end

      it 'should return true if the process has already been waited on' do
        @process.should_receive(:status).and_return(true)
        a = Accumulator.new(@process, [], [], [], [])
        a.tick.should be_true
      end
    end

    describe "#number_waiting_on" do
      it 'should return 0 when no pipes are left' do
        a = Accumulator.new(@process, [], [], [], [])
        a.number_waiting_on.should == 0
      end

      it 'should return 1 when one pipe is left' do
        pipe = flexmock("pipe")
        a = Accumulator.new(@process, [pipe], [nil], [], [])
        a.number_waiting_on.should == 1
      end

      it 'should return add readers and writers' do
        pipe = flexmock("pipe")
        a = Accumulator.new(@process, [pipe, pipe, pipe], [], [pipe], [])
        a.number_waiting_on.should == 4
      end

      it 'should transition from 0 to 1 as pipes are removed' do
        pipe = flexmock("pipe")
        read = flexmock("read")
        @process.should_receive(:status).and_return(nil)
        @process.should_receive(:status=)
        a = Accumulator.new(@process, [pipe], [read], [], [])
        flexmock(::IO).should_receive(:select).with([pipe], [], nil, 0.1).once.and_return([[pipe], [], []])
        pipe.should_receive(:eof?).and_return(true)
        pipe.should_receive(:close)
        flexmock(::Process).should_receive(:waitpid2).with(42, ::Process::WNOHANG).once.and_return(nil)
        a.number_waiting_on.should == 1
        a.tick.should be_false
        a.number_waiting_on.should == 0
      end
    end

    describe "#cleanup" do
      it 'should do nothing if no pipes are left open and the process is reaped' do
        @process.should_receive(:status).and_return(true)
        a = Accumulator.new(@process, [], [], [], [])
        flexmock(::Process).should_receive(:waitpid2).never
        a.cleanup
      end

      it 'should just call waitpid if no pipes are left open' do
        value = flexmock("value")
        a = Accumulator.new(@process, [], [], [], [])
        @process.should_receive(:status).and_return(nil)
        flexmock(::Process).should_receive(:waitpid2).with(42).once.and_return(value)
        @process.should_receive(:status=).with(value).once
        a.cleanup
      end

      it 'should close all open pipes' do
        a, b, c = flexmock("a"), flexmock("b"), flexmock("c")
        acc = Accumulator.new(@process, [a, b], [], [c], [])
        @process.should_receive(:status).and_return(true)
        [a, b].each {|fdes| fdes.should_receive(:close).with().once }
        [a, b].each {|fdes| fdes.should_receive(:closed?).and_return(false) }
        [c].each {|fdes| fdes.should_receive(:closed?).and_return(true) }
        flexmock(::Process).should_receive(:waitpid2).never
        acc.cleanup
      end

      it 'should close all open pipes and reap zombies if needed' do
        value = flexmock("value")
        a, b, c = flexmock("a"), flexmock("b"), flexmock("c")
        acc = Accumulator.new(@process, [b, c], [], [a], [])
        @process.should_receive(:status).and_return(nil)
        [a, b].each {|fdes| fdes.should_receive(:close).with().once }
        [a, b].each {|fdes| fdes.should_receive(:closed?).and_return(false) }
        [c].each {|fdes| fdes.should_receive(:closed?).and_return(true) }
        flexmock(::Process).should_receive(:waitpid2).with(42).once.and_return(value)
        @process.should_receive(:status=).with(value).once
        acc.cleanup
      end
    end

    describe "#run_to_completion" do
      it 'should run ticks until it is true' do
        value = flexmock("value")
        acc = flexmock(Accumulator.new(@process, [], [], [], []))
        acc.should_receive(:tick).with(value).times(3).and_return(false).and_return(false).and_return(true)
        acc.should_receive(:cleanup).once
        acc.should_receive(:number_waiting_on).and_return(1)
        acc.run_to_completion(value)
      end
      
      it 'should abort the loop early if there are no remaining pipes' do
        value = flexmock("value")
        acc = flexmock(Accumulator.new(@process, [], [], [], []))
        acc.should_receive(:tick).with(value).twice.and_return(false)
        acc.should_receive(:cleanup).once
        acc.should_receive(:number_waiting_on).and_return(1).and_return(0)
        acc.run_to_completion(value)
      end
      
      it 'should abort the loop after one iteration if there never were any pipes' do
        value = flexmock("value")
        acc = flexmock(Accumulator.new(@process, [], [], [], []))
        acc.should_receive(:tick).with(value).once.and_return(false)
        acc.should_receive(:cleanup).once
        acc.should_receive(:number_waiting_on).and_return(0)
        acc.run_to_completion(value)
      end
    end
  end
end
