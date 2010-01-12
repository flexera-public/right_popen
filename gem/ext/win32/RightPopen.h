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

#define MAX_ERROR_DESCRIPTION_LENGTH 511

// Summary:
//  represents an intermediary layer between Ruby and Windows implementations of popen.
class RightPopen
{
public:
	// HACK: MSVC 6.0 can't call a private destructor from a static class method,
	// so we can't use the full singleton pattern, DO NOT delete the singleton
	// object returned by getInstance()!
	~RightPopen();

    VALUE popen4(char* szCommand, int mode, bool bShowWindow, bool bAsynchronousOutput);
    VALUE asyncRead(VALUE vRubyIoObject);

    static RightPopen& getInstance();

private:
    RightPopen();
    RightPopen(const RightPopen&);

    RightPopen& operator=(const RightPopen&);

    VALUE allocateRubyIoObject();
    VALUE createRubyIoObject(DWORD pid, int iFileMode, HANDLE hFile, bool bReadMode);

    int parseRubyIoModeFlags(const char* szMode);

    char* getErrorDescription(DWORD dwErrorCode);

    char m_errorDescriptionBuffer[MAX_ERROR_DESCRIPTION_LENGTH + 1];
};
