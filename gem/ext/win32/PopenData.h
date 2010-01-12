///////////////////////////////////////////////////////////////////////////////
// Copyright (c) 2010 RightScale Inc
//
// Permission is hereby granted, free of charge, to any person obtaining
// a copy of this software and associated documentation files (the
// "Software"), to deal in the Software without restriction, including
// without limitation the rights to use, copy, modify, merge, publish,
// distribute, sublicense, and/or sell copies of the Software, and to
// permit persons to whom the Software is furnished to do so, subject to
// the following conditions:
//
// The above copyright notice and this permission notice shall be
// included in all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
// EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
// MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
// NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
// LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
// OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
// WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
///////////////////////////////////////////////////////////////////////////////

#pragma once

#include "PopenAsyncIOData.h"
#include "PopenIOHandlePair.h"

// Summary:
//  represents fields and data needed to manage standard I/O for a child process
//  connected by pipes to the calling process. supports asynchronous I/O to
//  avoid a deadlock issue caused by the child process blocking during attempt
//  to write to a full pipe buffer while the calling process is blocked
//  attempting to read an unflushed pipe buffer. asynchronous I/O is necessary
//  whenever the child process produces more than a total of about 4KB of output
//  from either stdout or stderr.
class PopenData
{
public:
    PopenData();
    ~PopenData();

    bool hasIOObject(VALUE vRubyIoObject) const;

    VALUE getStdinWriteIOObject() { return m_vStdinWrite; }
    VALUE getStdoutReadIOObject() { return m_vStdoutRead; }
    VALUE getStderrReadIOObject() { return m_vStderrRead; }

    PopenIOHandlePair& getChildStdinPair() { return *m_pChildStdinPair; }
    PopenIOHandlePair& getChildStdoutPair() { return *m_pChildStdoutPair; }
    PopenIOHandlePair& getChildStderrPair() { return *m_pChildStderrPair; }

    DWORD getExitCode() const { return m_dwExitCode; }
    DWORD getOpenFileCount() const { return m_dwOpenFileCount; }
    DWORD getProcessId() const { return m_dwProcessId; }

    void attachRubyIOObjects(VALUE vStdinWrite, VALUE vStdoutRead, VALUE vStderrRead);
    void createAsyncIOData();

    bool createProcess(char* szCommand, bool bShowWindow);
    bool notifyFinalized(OpenFile* pOpenFile);

    VALUE asyncRead(VALUE vRubyIoObject);

    static PopenData* findByProcessId(DWORD pid);
    static PopenData* findByRubyIOObject(VALUE vRubyIoObject);

private:
    void addToList();
    void removeFromList();

    // FIX: the MSVC 6.0 compiler introduces a crash if the PopenIOHandlePair*
    // members are not declared before the other members. the MSVC 7.1 compiler
    // does not have this problem. the crash is probably the result of a 6.0
    // compiler bug, but it might be possible to turn off optimization and avoid
    // it that way. just leave the members where they are for now.
    PopenIOHandlePair* m_pChildStdinPair;
    PopenIOHandlePair* m_pChildStdoutPair;
    PopenIOHandlePair* m_pChildStderrPair;

    // the rest of these can be reordered safely, it seems.
    PopenData*         m_pPrevious;
    PopenData*         m_pNext;
    PopenAsyncIOData*  m_pStdoutAsyncIOData;
    PopenAsyncIOData*  m_pStderrAsyncIOData;
    HANDLE             m_hProcess;
    DWORD              m_dwExitCode;
    DWORD              m_dwProcessId;
    DWORD              m_dwOpenFileCount;
    VALUE              m_vStdinWrite;
    VALUE              m_vStdoutRead;
    VALUE              m_vStderrRead;

    static const DWORD CHILD_PROCESS_EXIT_WAIT_MSECS;
    static PopenData*  m_list;
};
