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
