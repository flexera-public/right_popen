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
  describe Utilities do
    describe :run do
      it 'should collect stdout and stderr' do
        out, err = Utilities::run("echo foo; echo bar >&2")
        out.should == "foo\n"
        err.should == "bar\n"
      end

      it 'should handle utilities that expect input' do
        out, err = Utilities::run("echo foo; read; echo bar >&2")
        out.should == "foo\n"
        err.should == "bar\n"
      end

      it 'should raise an error if the command fails' do
        lambda { Utilities::run("false") }.should raise_exception(/Command "false" failed with exit status 1/)
      end

      it 'should raise an error if the command gets killed' do
        lambda { Utilities::run("kill $$") }.should raise_exception(/Command ".*" failed due to SIGTERM/)
      end

      it 'should not invoke the shell when inappropriate' do
        out, err = Utilities::run(["echo", "foo;", "echo", "bar", ">&2"])
        out.should == "foo; echo bar >&2\n"
        err.should be_empty
      end
    end

    describe :run_collecting_output do
      it 'should work' do
        status, out, err = Utilities::run_collecting_output("echo foo; echo bar >&2")
        status.should be_success
        out.should == "foo\n"
        err.should == "bar\n"
      end

      it 'should handle the command failing gracefully' do
        status, out, err = Utilities::run_collecting_output("false")
        status.should_not be_success
        status.exitstatus.should == 1
        out.should be_empty
        err.should be_empty
      end

      it 'should handle the command self terminating gracefully' do
        status, out, err = Utilities::run_collecting_output("kill $$")
        status.should_not be_success
        status.exitstatus.should be_nil
        status.termsig.should == 15
        out.should be_empty
        err.should be_empty
      end

      it 'should not invoke the shell when inappropriate' do
        status, out, err = Utilities::run_collecting_output(["echo", "foo;", "read", "foo", ";", "echo", "bar", ">&2"])
        status.should be_success
        out.should == "foo; read foo ; echo bar >&2\n"
        err.should be_empty
      end
    end

    describe :run_with_stdin_collecting_output do
      it 'should work even if subprocess ignores stdin' do
        status, out, err = Utilities::run_with_stdin_collecting_output("echo foo; echo bar >&2", "foo")
        status.should be_success
        out.should == "foo\n"
        err.should == "bar\n"
      end

      it 'should handle utilities that expect input' do
        status, out, err = Utilities::run_with_stdin_collecting_output("echo foo; read foo; echo $foo >&2", "blotz")
        status.should be_success
        out.should == "foo\n"
        err.should == "blotz\n"
      end

      it 'should handle the command failing gracefully' do
        status, out, err = Utilities::run_with_stdin_collecting_output("false", "blotz")
        status.should_not be_success
        status.exitstatus.should == 1
        out.should be_empty
        err.should be_empty
      end

      it 'should handle the command self terminating gracefully' do
        status, out, err = Utilities::run_with_stdin_collecting_output("kill $$", "blotz")
        status.should_not be_success
        status.exitstatus.should be_nil
        status.termsig.should == 15
        out.should be_empty
        err.should be_empty
      end

      it 'should not invoke the shell when inappropriate' do
        status, out, err = Utilities::run_with_stdin_collecting_output(["echo", "foo;", "read", "foo", ";", "echo", "bar", ">&2"], "blotz")
        status.should be_success
        out.should == "foo; read foo ; echo bar >&2\n"
        err.should be_empty
      end
    end

    describe :run_with_blocks do
      it 'should work even if subprocess ignores stdin' do
        status = Utilities::run_with_blocks("echo foo; echo bar >&2",
                                            lambda { "foo" },
                                            lambda { |b| b.should == "foo\n" },
                                            lambda { |b| b.should == "bar\n" })
        status.should be_success
      end

      it 'should handle interaction' do
        output_counter = 0
        seen = {}
        in_block = lambda {
          if seen[output_counter]
            ""
          else
            seen[output_counter] = true
            "foo\n"
          end
        }
        status = Utilities::run_with_blocks("for x in 1 2 3; do read var; echo $var; done; echo bar >&2",
                                            in_block,
                                            lambda { |b| output_counter += 1; b.should == "foo\n" },
                                            lambda { |b| b.should == "bar\n" })
        status.should be_success
        output_counter.should == 3
      end

      it 'should handle the command failing gracefully' do
        status = Utilities::run_with_blocks("echo foo; echo bar >&2; false",
                                            lambda { "blotz" }, nil, nil)
        status.should_not be_success
        status.exitstatus.should == 1
      end

      it 'should handle the command self terminating gracefully' do
        status = Utilities::run_with_blocks("echo foo; echo bar >&2; kill $$",
                                            lambda { "blotz" }, nil, nil)
        status.should_not be_success
        status.exitstatus.should be_nil
        status.termsig.should == 15
      end

      it 'should not invoke the shell when inappropriate' do
        status, out, err = Utilities::run_with_blocks(["echo", "foo;", "read", "foo", ";", "echo", "bar", ">&2"], nil, lambda {|b| b.should == "foo; read foo ; echo bar >&2\n"}, nil)
        status.should be_success
      end
    end
  end
end
