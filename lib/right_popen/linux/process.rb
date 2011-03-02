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

require 'etc'

module RightScale
  module RightPopen
    class Process
      attr_reader :pid, :stdin, :stdout, :stderr, :status_fd
      attr_accessor :status
      
      def initialize(parameters={})
        parameters[:locale] = true unless parameters.has_key?(:locale)
        @parameters = parameters
        @status_fd = nil
      end
      
      def fork(cmd)
        @cmd = cmd
        stdin_r, stdin_w = IO.pipe
        stdout_r, stdout_w = IO.pipe
        stderr_r, stderr_w = IO.pipe
        status_r, status_w = IO.pipe

        [stdin_r, stdin_w, stdout_r, stdout_w,
         stderr_r, stderr_w, status_r, status_w].each {|fdes| fdes.sync = true}

        @pid = Kernel::fork do
          begin
            stdin_w.close
            STDIN.reopen stdin_r

            stdout_r.close
            STDOUT.reopen stdout_w

            stderr_r.close
            STDERR.reopen stderr_w

            status_r.close
            status_w.fcntl(Fcntl::F_SETFD, Fcntl::FD_CLOEXEC)
            
            if group = get_group
              ::Process.egid = group
              ::Process.gid = group
            end

            if user = get_user
              ::Process.euid = user
              ::Process.uid = user
            end

            Dir.chdir(@parameters[:directory]) if @parameters[:directory]

            ENV["LC_ALL"] = "C" if @parameters[:locale]
          
            @parameters[:environment].each do |key,value|
              ENV[key.to_s] = value.to_s
            end if @parameters[:environment]

            File.umask(get_umask) if @parameters[:umask]

            if cmd.kind_of?(Array)
              exec(*cmd)
            else
              exec("sh", "-c", cmd)
            end
            raise 'forty-two' 
          rescue Exception => e
            Marshal.dump(e, status_w)
          end
          status_w.close
          exit!
        end

        stdin_r.close
        stdout_w.close
        stderr_w.close
        status_w.close
        @stdin = stdin_w
        @stdout = stdout_r
        @stderr = stderr_r
        @status_fd = status_r
      end

      def wait_for_exec
        begin
          e = Marshal.load @status_fd
          # thus meaning that the process failed to exec...
          @stdin.close
          @stdout.close
          @stderr.close
          raise(Exception === e ? e : "unknown failure!")
        rescue EOFError
          # thus meaning that the process did exec and we can continue.
        ensure
          @status_fd.close
        end
      end

      private

      def get_user
        user = @parameters[:user] || nil
        unless user.kind_of?(Integer)
          user = Etc.getpwnam(user).uid if user
        end
        user
      end

      def get_group
        group = @parameters[:group] || nil
        unless group.kind_of?(Integer)
          group = Etc.getgrnam(group).gid if group
        end
        group
      end

      def get_umask
        if @parameters[:umask].respond_to?(:oct)
          value = @parameters[:umask].oct
        else
          value = @parameters[:umask].to_i
        end
        value & 007777
      end
    end
  end
end
