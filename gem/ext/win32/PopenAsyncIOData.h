#pragma once

#include "rubymain.h"

#define ASYNC_IO_BUFFER_SIZE (1 << 12)  // 4KB

// Summary:
//  encapsulates methods and fields needed to perform asynchronous read I/O.
class PopenAsyncIOData
{
public:
    PopenAsyncIOData(HANDLE hRead);
    ~PopenAsyncIOData();

    VALUE asyncRead();

private:
    HANDLE     m_hRead;
    DWORD      m_dwBytesRead;
    OVERLAPPED m_overlapped;
    char       m_buffer[ASYNC_IO_BUFFER_SIZE + 1];  // buffer size plus nul guard byte
    bool       m_bPending;
};
