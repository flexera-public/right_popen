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

#include "PopenIOHandlePair.h"

DWORD PopenIOHandlePair::m_namedPipeSerialNumber = 1;

PopenIOHandlePair::PopenIOHandlePair(HANDLE hRead, HANDLE hWrite)
    : m_hRead(hRead),
      m_hWrite(hWrite)
{
}

PopenIOHandlePair::PopenIOHandlePair(const PopenIOHandlePair& other)
    : m_hRead(other.m_hRead),
      m_hWrite(other.m_hWrite)
{
}

PopenIOHandlePair::~PopenIOHandlePair()
{
   if (NULL != m_hRead)
   {
      CloseHandle(m_hRead);
      m_hRead = NULL;
   }
   if (NULL != m_hWrite)
   {
      CloseHandle(m_hWrite);
      m_hWrite = NULL;
   }
}

PopenIOHandlePair& PopenIOHandlePair::operator=(const PopenIOHandlePair& other)
{
    if (this != &other)
    {
        m_hRead  = other.m_hRead;
        m_hWrite = other.m_hWrite;
    }

    return *this;
}

HANDLE PopenIOHandlePair::forgetRead()
{
    HANDLE hTemp = m_hRead;

    m_hRead = NULL;

    return hTemp; 
}

HANDLE PopenIOHandlePair::forgetWrite()
{
    HANDLE hTemp = m_hWrite;

    m_hWrite = NULL;

    return hTemp;
}

// Summary:
//  creates an asynchronous pipe which allows for a single-threaded process
//  (e.g. Ruby v1.8) to read from multiple open pipes without deadlocking.
//  the write handle can be opened for any combination of synchronous/
//  asynchronous read/write. in the case of reading stdout and stderr from a
//  child process, open the pipe with synchronous write and asynchronous read
//  which means that only the caller and not the child process needs to be
//  aware that the pipe uses asynchronous read calls.
//
// Parameters:
//  pReadPipeHandle
//      receives created synchronous read pipe handle
//
//  pWritePipeHandle
//      receives opened asynchronous write pipe handle
//
//  pPipeAttributes
//      security attributes or NULL
//
//  nSize
//      suggested pipe buffer size or zero
//
//  dwReadMode
//      read mode, which can be FILE_FLAG_OVERLAPPED or zero
//
//  dwWriteMode
//      write mode, which can be FILE_FLAG_OVERLAPPED or zero
//
// Returns:
//  true if successful, false on failure (call GetLastError() for more info)
bool PopenIOHandlePair::createAsynchronousPipe(SECURITY_ATTRIBUTES* pPipeAttributes,
                                               DWORD                nSize,
                                               DWORD                dwReadMode,
                                               DWORD                dwWriteMode)
{
    // only one valid mode flag - FILE_FLAG_OVERLAPPED
    if ((dwReadMode | dwWriteMode) & (~FILE_FLAG_OVERLAPPED))
    {
        ::SetLastError(ERROR_INVALID_PARAMETER);
        return FALSE;
    }

    // default buffer size to 4 KB.
    {
        const DWORD nMinBufferSize = 1 << 12;

        nSize = max(nSize, nMinBufferSize);
    }

    // generate unique pipe name.
    char pipeNameBuffer[MAX_PATH];

    sprintf(pipeNameBuffer,
            "\\\\.\\Pipe\\Ruby_Win32_Open3_gem.%d.%d",
            (int)GetCurrentProcessId(),
            (int)m_namedPipeSerialNumber++);

    // create read-end of pipe.
    m_hRead = ::CreateNamedPipeA(pipeNameBuffer,
                                 PIPE_ACCESS_INBOUND | dwReadMode,
                                 PIPE_TYPE_BYTE | PIPE_WAIT,
                                 1,      // allowed named pipe instances
                                 nSize,  // out buffer size
                                 nSize,  // in buffer size
                                 0,      // default timeout = 50 ms
                                 pPipeAttributes);

    if (NULL == m_hRead || INVALID_HANDLE_VALUE == m_hRead)
    {
        return false;
    }

    // open write-end of existing pipe.
    m_hWrite = ::CreateFileA(pipeNameBuffer,
                             GENERIC_WRITE,
                             0,  // No sharing
                             pPipeAttributes,
                             OPEN_EXISTING,
                             FILE_ATTRIBUTE_NORMAL | dwWriteMode,
                             NULL);

    return (NULL != m_hWrite && INVALID_HANDLE_VALUE != m_hWrite);
}

// Summary:
//  creates a pipe and manages the requested inheritance for read/write. this
//  allows the inheritable handles to be passed to a created child process.
//
// Parameters:
//  bInheritRead
//      true if read handle will be inheritable.
//     
//  bInheritWrite
//      true if write handle will be inheritable.
//
//  bAsynchronousOutput
//      true if read handle supports overlapped IO API calls, false if reads
//      are synchronous. the write handle is always synchronous so that the
//      child process can perform simple writes to stdout/stderr.
//
// Returns:
//  true if successful, false on failure (call GetLastError() for more info)
bool PopenIOHandlePair::createPipe(BOOL bInheritRead,
                                   BOOL bInheritWrite,
                                   BOOL bAsynchronousOutput)
{
    // self check.
    if (NULL != m_hRead || NULL != m_hWrite)
    {
        ::SetLastError(ERROR_INVALID_STATE);
        return false;
    }

    // create pipe without inheritance, if requested.
    if (0 == bInheritRead && 0 == bInheritWrite)
    {
        BOOL bResult = bAsynchronousOutput
                     ? createAsynchronousPipe(NULL, 0, FILE_FLAG_OVERLAPPED, 0)
                     : ::CreatePipe(getReadPtr(), getWritePtr(), NULL, 0);

        return (0 != bResult);
    }
    else
    {
        HANDLE hCurrentProcess = GetCurrentProcess();
        SECURITY_ATTRIBUTES sa;

        // create pipe with inheritable flag set to TRUE.
        ::ZeroMemory(&sa, sizeof(sa));
        sa.nLength = sizeof(sa);
        sa.bInheritHandle = TRUE;
        {
            BOOL bResult = bAsynchronousOutput
                         ? createAsynchronousPipe(&sa, 0, FILE_FLAG_OVERLAPPED, 0)
                         : ::CreatePipe(getReadPtr(), getWritePtr(), &sa, 0);

            if (0 == bResult)
            {
                return false;
            }
        }

        // duplicate the uninheritable handle (if any) by setting inheritance to FALSE.
        // otherwise, the child inherits the these handles which results in
        // non-closeable handles to the pipes being created.
        if (0 == bInheritRead)
        {
            HANDLE hRead = forgetRead();
            BOOL bSuccess = ::DuplicateHandle(hCurrentProcess,
                                              hRead,
                                              hCurrentProcess,
                                              getReadPtr(),
                                              0,
                                              FALSE,
                                              DUPLICATE_SAME_ACCESS);
            ::CloseHandle(hRead);
            hRead = NULL;
            if (0 == bSuccess)
            {
                return false;
            }
        }
        if (0 == bInheritWrite)
        {
            HANDLE hWrite = forgetWrite();
            BOOL bSuccess = ::DuplicateHandle(hCurrentProcess,
                                              hWrite,
                                              hCurrentProcess,
                                              getWritePtr(),
                                              0,
                                              FALSE,
                                              DUPLICATE_SAME_ACCESS);
            ::CloseHandle(hWrite);
            hWrite = NULL;
            if (0 == bSuccess)
            {
                return false;
            }
        }
    }

    return true;
}
