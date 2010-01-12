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

#include "PopenAsyncIOData.h"

PopenAsyncIOData::PopenAsyncIOData(HANDLE hRead)
    : m_hRead(hRead),
      m_dwBytesRead(0),
      m_bPending(false)
{
    // reset.
    ::ZeroMemory(&m_overlapped, sizeof(m_overlapped));
    ::ZeroMemory(m_buffer, sizeof(m_buffer));

    // create asynchronous read event in a signalled state (meaning ready for next I/O operation).
    m_overlapped.hEvent = ::CreateEvent(NULL, TRUE, TRUE, NULL);
}

PopenAsyncIOData::~PopenAsyncIOData()
{
    // must attempt to cancel any pending I/O operation or else blocked system
    // thread may wake and attempt to use deleted buffer, etc.
    if (m_bPending)
    {
        BOOL bResult = ::CancelIo(m_hRead);

        if (FALSE != bResult || ERROR_NOT_FOUND != ::GetLastError())
        {
            // wait for the I/O subsystem to acknowledge our cancellation.
            // depending on the timing of the calls, the I/O might complete
            // with a cancellation status, or it might complete normally (if
            // the ReadFile() was in the process of completing at the time
            // CancelIo() was called, or if the device does not support
            // cancellation). this call specifies TRUE for the bWait parameter,
            // which will block until the I/O either completes or is canceled,
            // thus resuming execution, provided the underlying device driver
            // and associated hardware are functioning properly. if there is a
            // problem with the driver it is better to stop responding, or
            // "hang," here than to try to continue while masking the problem.
            ::GetOverlappedResult(m_hRead, &m_overlapped, &m_dwBytesRead, TRUE);
        }
        m_bPending = false;
    }
    if (NULL != m_overlapped.hEvent)
    {
        ::CloseHandle(m_overlapped.hEvent);
        m_overlapped.hEvent = NULL;
    }
}

// Summary:
//  asynchronously reads from the associated read handle.
//
// Returns:
//  Ruby string object representing a completed asynchronous read OR
//  the empty string to indicate the read is pending OR
//  Qnil to indicate data is not available and no further attempt to read should be made
VALUE PopenAsyncIOData::asyncRead()
{
    // nothing to do if asynchronous read event has not been signalled.
    if (WAIT_OBJECT_0 == ::WaitForSingleObject(m_overlapped.hEvent, 0))
    {
        // attempt to complete last read without waiting if pending.
        if (m_bPending)
        {
            if (0 == ::GetOverlappedResult(m_hRead, &m_overlapped, &m_dwBytesRead, FALSE)) 
            {
                DWORD dwErrorCode = ::GetLastError();

                switch (dwErrorCode)
                {
                case ERROR_IO_INCOMPLETE:
                    break;
                default:
                    // doesn't matter why read failed; read is no longer
                    // pending and was probably cancelled.
                    m_bPending = false;
                    return Qnil;
                }
            }
            else
            {
                // delayed read completed, set guard byte to nul.
                m_bPending = false;
                m_buffer[m_dwBytesRead] = 0;
            }
        }
        else if (0 == ::ReadFile(m_hRead, m_buffer, sizeof(m_buffer) - 1, &m_dwBytesRead, &m_overlapped))
        {
            DWORD dwErrorCode = GetLastError();

            switch (dwErrorCode)
            {
            case ERROR_IO_PENDING: 
                m_bPending = true;
                break;
            default:
                // doesn't matter why read failed; data is no longer available.
                return Qnil;
            }
        }
        else
        {
            // read completed immediately, set guard byte to nul.
            m_buffer[m_dwBytesRead] = 0;
        }
    }

    // the overlapped I/O appears to pass \r\n literally from the child
    // process' output stream whereas the synchronous stdio alternative
    // replaces \r\n with \n. for the sake of homogeneity of text data
    // and the fact that Ruby code rarely uses the \r\n idiom, quickly
    // remove all \r characters from the text.
    if (m_dwBytesRead > 0)
    {
        char* pszInsert = m_buffer;
        char* pszParse = m_buffer;
        char* pszStop = m_buffer + m_dwBytesRead;

        while (pszParse < pszStop)
        {
            char chNext = *pszParse++;
            if ('\r' != chNext)
            {
                *pszInsert++ = chNext;
            }
        }
        m_dwBytesRead = (DWORD)(pszInsert - m_buffer);
    }

    // create string for return value, if necessary. the empty string signals
    // that the caller should keep trying (i.e. pending).
    return rb_str_new(m_buffer, (long)m_dwBytesRead);
}
