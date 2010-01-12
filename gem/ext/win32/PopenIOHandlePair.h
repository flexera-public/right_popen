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

#include "rubymain.h"

// Summary:
//  represents a pair of I/O handles (read/write) with some helper methods for
//  creating pipes of various flavors under Windows.
class PopenIOHandlePair
{
public:
    PopenIOHandlePair(HANDLE hRead = NULL, HANDLE hWrite = NULL);
    ~PopenIOHandlePair();

    HANDLE getRead() const  { return m_hRead; }
    HANDLE getWrite() const { return m_hWrite; }

    HANDLE* getReadPtr()  { return &m_hRead; }
    HANDLE* getWritePtr() { return &m_hWrite; }

    HANDLE forgetRead();
    HANDLE forgetWrite();

    bool createPipe(BOOL bInheritRead, BOOL bInheritWrite, BOOL bAsynchronousOutput);

protected:
    bool createAsynchronousPipe(SECURITY_ATTRIBUTES* pPipeAttributes,
                                DWORD                nSize,
                                DWORD                dwReadMode,
                                DWORD                dwWriteMode);

private:
    PopenIOHandlePair(const PopenIOHandlePair&);

    PopenIOHandlePair& operator=(const PopenIOHandlePair&);

    HANDLE m_hRead;
    HANDLE m_hWrite;

    static DWORD m_namedPipeSerialNumber;
};
