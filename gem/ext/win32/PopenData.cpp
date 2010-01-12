#include "PopenData.h"

PopenData* PopenData::m_list = NULL;

const DWORD PopenData::CHILD_PROCESS_EXIT_WAIT_MSECS = 500;    // 0.5 secs

PopenData::PopenData()
    : m_pChildStdinPair(NULL),
      m_pChildStdoutPair(NULL),
      m_pChildStderrPair(NULL),
      m_pPrevious(NULL),
      m_pNext(NULL),
      m_pStdoutAsyncIOData(NULL),
      m_pStderrAsyncIOData(NULL),
      m_hProcess(NULL),
      m_dwOpenFileCount(0),
      m_dwExitCode(0),
      m_dwProcessId(0),
      m_vStdinWrite(Qnil),
      m_vStdoutRead(Qnil),
      m_vStderrRead(Qnil)
{
    m_pChildStdinPair = new PopenIOHandlePair();
    m_pChildStdoutPair = new PopenIOHandlePair();
    m_pChildStderrPair = new PopenIOHandlePair();
    addToList();
}

PopenData::~PopenData()
{
    removeFromList();
    if (NULL != m_pStdoutAsyncIOData)
    {
        delete m_pStdoutAsyncIOData;
        m_pStdoutAsyncIOData = NULL;
    }
    if (NULL != m_pStderrAsyncIOData)
    {
        delete m_pStderrAsyncIOData;
        m_pStderrAsyncIOData = NULL;
    }
    if (NULL != m_hProcess)
    {
        ::CloseHandle(m_hProcess);
        m_hProcess = NULL;
    }
    delete m_pChildStdinPair;
    m_pChildStdinPair = NULL;
    delete m_pChildStdoutPair;
    m_pChildStdoutPair = NULL;
    delete m_pChildStderrPair;
    m_pChildStderrPair = NULL;
}

// Summary:
//  determines if the given Ruby I/O object was created for this popen instance.
//
// Parameters:
//   vRubyIoObject
//      candidate I/O object (or possibly some other kind of Ruby value).
//
// Returns:
//  true if I/O object is associated with this popen instance.
bool PopenData::hasIOObject(VALUE vRubyIoObject) const
{
    return (vRubyIoObject == m_vStdoutRead || vRubyIoObject == m_vStderrRead);
}

// Summary:
//  attaches the given Ruby I/O objects to this popen instance.
//
// Parameters:
//   vStdinWrite
//      stdin write object
//
//   vStdoutRead
//      stdout read object
//
//   vStderrRead
//      stderr read object
void PopenData::attachRubyIOObjects(VALUE vStdinWrite, VALUE vStdoutRead, VALUE vStderrRead)
{
    m_vStdinWrite = vStdinWrite;
    m_vStdoutRead = vStdoutRead;
    m_vStderrRead = vStderrRead;
    m_dwOpenFileCount = 3;
}

// Summary:
//  creates and attaches the asynchonous I/O data objects used to asynchronously
//  read stdout and stderr from the child process.
void PopenData::createAsyncIOData()
{
    m_pStdoutAsyncIOData = new PopenAsyncIOData(m_pChildStdoutPair->getRead());
    m_pStderrAsyncIOData = new PopenAsyncIOData(m_pChildStderrPair->getRead());
}

// Summary:
//  inserts this into double-ended linked list.
void PopenData::addToList()
{
    if (NULL == m_list)
    {
        m_list = this;
    }
    else
    {
        m_pNext = m_list;
        m_list->m_pPrevious = this;
        m_list = this;
    }
}

// Summary:
//  removes this from double-ended linked list.
void PopenData::removeFromList()
{
    if (NULL != m_pPrevious)
    {
        m_pPrevious->m_pNext = m_pNext;
    }
    if (NULL != m_pNext)
    {
        m_pNext->m_pPrevious = m_pPrevious;
    }
    m_pPrevious = NULL;
    m_pNext = NULL;
}

// Summary:
//  creates a process using the popen pipe handles for standard I/O.
//
// Parameters:
//   cszCommand
//      command to execute
//
//   bShowWindow
//      true if process window is initially visible, false if process has no UI or is invisible
//
// Returns:
//  true if successful, false otherwise (call GetLastError() for more information)
bool PopenData::createProcess(const char* szCommand, bool bShowWindow)
{
    // self check.
    if (NULL != m_hProcess)
    {
        ::SetLastError(ERROR_INVALID_STATE);
        return false;
    }

    // prepare startup info using pipe handles for child I/O.
    STARTUPINFO si;

    ::ZeroMemory(&si, sizeof(si));
    si.cb          = sizeof(STARTUPINFO);
    si.dwFlags     = STARTF_USESTDHANDLES | STARTF_USESHOWWINDOW;
    si.hStdInput   = m_pChildStdinPair->getRead();
    si.hStdOutput  = m_pChildStdoutPair->getWrite();
    si.hStdError   = m_pChildStderrPair->getWrite();
    si.wShowWindow = bShowWindow ? SW_SHOW : SW_HIDE;

    // create process.
    PROCESS_INFORMATION pi;

    ::ZeroMemory(&pi, sizeof(pi));

    BOOL bResult = CreateProcessA(NULL, (LPSTR)szCommand, NULL, NULL, TRUE, 0, NULL, NULL, &si, &pi);

    if (0 == bResult)
    {
        return false;
    }

    // close our copy of thread handle now instead of keeping it.
    CloseHandle(pi.hThread);

    // keep process details.
    m_hProcess    = pi.hProcess;
    m_dwProcessId = pi.dwProcessId;

    return true;
}

// Summary:
//  asynchronously reads from the given Ruby I/O object and handles any pending
//  states to simplify reading for the caller.
//
// Parameters:
//   vRubyIoObject
//      read object associated with this popen instance
//
// Returns:
//  Ruby string object representing a completed asynchronous read OR
//  the empty string to indicate the read is pending OR
//  Qnil to indicate data is not available and no further attempt to read should be made
VALUE PopenData::asyncRead(VALUE vRubyIoObject)
{
    // attempt to find corresponding asynchronous I/O data.
    bool bStdout = m_vStdoutRead == vRubyIoObject;
    PopenAsyncIOData* pPopenAsyncIOData = bStdout ? m_pStdoutAsyncIOData : m_pStderrAsyncIOData;

    return pPopenAsyncIOData->asyncRead();
}

// Summary:
//  notification that an associated Ruby file object has been finalized.
//
// Parameters:
//   pFile
//      finalized file object
//
// Returns:
//  true if all associated file objects have been finalized
bool PopenData::notifyFinalized(OpenFile* /*pOpenFile*/)
{
    if (m_dwOpenFileCount <= 1)
    {
        // unlink.
        m_dwOpenFileCount = 0;

        // forget the pipe handles owned by the Ruby I/O objects to avoid
        // attempting to again close the already-closed handles.
        m_pChildStdinPair->forgetWrite();
        m_pChildStdoutPair->forgetRead();
        m_pChildStderrPair->forgetRead();

        return true;
    }

    // at least one more associated file left to close.
    --m_dwOpenFileCount;

    return false;
}

// Summary:
//  attempts to find popen data by process id in the linked list.
//
// Returns:
//  matching popen data or NULL
PopenData* PopenData::findByProcessId(DWORD pid)
{
    for (PopenData* pPopenData = m_list; pPopenData != NULL; pPopenData = pPopenData->m_pNext)
    {
        if (pid == pPopenData->m_dwProcessId)
        {
            return pPopenData;
        }
    }

    return NULL;
}

// Summary:
//  attempts to find popen data by associated Ruby I/O object in the linked
//  list.
//
// Returns:
//  matching popen data or NULL
PopenData* PopenData::findByRubyIOObject(VALUE vRubyIoObject)
{
    for (PopenData* pPopenData = m_list; pPopenData != NULL; pPopenData = pPopenData->m_pNext)
    {
        if (pPopenData->hasIOObject(vRubyIoObject))
        {
            return pPopenData;
        }
    }

    return NULL;
}
