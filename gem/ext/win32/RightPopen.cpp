#include "RightPopen.h"
#include "PopenData.h"

RightPopen::RightPopen()
{
    ::ZeroMemory(m_errorDescriptionBuffer, sizeof(m_errorDescriptionBuffer));
}

RightPopen::~RightPopen()
{
}

// Summary:
//  singleton method
//
// Returns:
//  singleton
RightPopen& RightPopen::getInstance()
{
    static RightPopen instance;

    return instance;
}

// Summary:
//  finalizer for the given Ruby file object.
//
// Parameters:
//   pOpenFile
//      internal Ruby OpenFile struct from Ruby I/O object
//
//   noraise
//      indicates whether or not raising exceptions is allowed
extern "C"
{
    static void right_popen_pipe_finalize(OpenFile* pOpenFile, int noraise)
    {
        if (pOpenFile->f)
        {
            fclose(pOpenFile->f);
            pOpenFile->f = NULL;
        }

        if (pOpenFile->f2)
        {
            fclose(pOpenFile->f2);
            pOpenFile->f2 = NULL;
        }

        // update exit status for child process, etc.
        PopenData* pPopenData = PopenData::findByProcessId(pOpenFile->pid);

        if (NULL != pPopenData && pPopenData->notifyFinalized(pOpenFile))
        {
            delete pPopenData;
        }
    }
}

// Summary:
//  allocates a new Ruby I/O object.
//
// Returns:
//  partially initialized I/O object.
VALUE RightPopen::allocateRubyIoObject()
{
    VALUE klass = rb_cIO;

    NEWOBJ(io, struct RFile);
    OBJSETUP(io, klass, T_FILE);

    io->fptr = 0;

    return (VALUE)io;
}

// Summary:
//  parses the given mode string for Ruby mode flags.
//
// Returns:
//  integer representation of mode flags
int RightPopen::parseRubyIoModeFlags(const char* szMode)
{
    int flags = 0;
    BOOL bValid = TRUE;

    switch (szMode[0])
    {
    case 'r':
         flags |= FMODE_READABLE;
         break;
    case 'w':
    case 'a':
         flags |= FMODE_WRITABLE;
         break;
    default:
        bValid = FALSE;
    }
    if (bValid)
    {
        if (szMode[1] == 'b')
        {
            flags |= FMODE_BINMODE;
            szMode++;
        }
        if (szMode[1] == '+')
        {
            if (szMode[2] == 0)
            {
                flags |= FMODE_READWRITE;
            }
            else
            {
                bValid = FALSE;
            }
        }
        else if (szMode[1] != 0)
        {
            bValid = FALSE;
        }
    }
    if (FALSE == bValid)
    {
        rb_raise(rb_eArgError, "illegal access mode %s", szMode);
    }

    return flags;
}

// Summary:
//  gets text for the given error code.
//
// Parameters:
//   dwErrorCode
//      win32 error code
//
// Returns:
//  formatted error string
char* RightPopen::getErrorDescription(DWORD dwErrorCode)
{
   HLOCAL hLocal = NULL;
   DWORD dwFlags = FORMAT_MESSAGE_ALLOCATE_BUFFER | FORMAT_MESSAGE_FROM_SYSTEM | FORMAT_MESSAGE_IGNORE_INSERTS;
   int iLength = ::FormatMessageA(dwFlags,
                                  NULL,
                                  dwErrorCode,
                                  MAKELANGID(LANG_NEUTRAL, SUBLANG_DEFAULT),
                                  (char*)&hLocal,
                                  0,
                                  NULL);
    if (0 == iLength)
    {
        sprintf(m_errorDescriptionBuffer, "Unable to format message for Windows error #%d", (int)dwErrorCode);
    }
    else
    {
        memset(m_errorDescriptionBuffer, 0, sizeof(m_errorDescriptionBuffer));
        strncpy(m_errorDescriptionBuffer, (LPTSTR)hLocal, iLength - 2);  // remove \r\n
        ::LocalFree(hLocal);
    }

    return m_errorDescriptionBuffer;
}

// creates a Ruby I/O object from a file (pipe) handle opened for read or write.
//
// Parameters:
//     pid
//         child process id using the other end of pipe
//
//     mode
//         standard I/O file mode
//
//     hFile
//         pipe I/O connector to wrap with Ruby object
//
//     bReadMode
//         true to create a readonly file object, false to create a writeonly file object.
//
// Returns:
//     a Ruby I/O object
VALUE RightPopen::createRubyIoObject(DWORD pid, int iFileMode, HANDLE hFile, bool bReadMode)
{
    BOOL bTextMode = 0 != (iFileMode & _O_TEXT);
    char* szMode = bReadMode
                 ? (bTextMode ? "r" : "rb")
                 : (bTextMode ? "w" : "wb");
    int fd = _open_osfhandle((long)hFile, iFileMode);
    FILE* pFile = _fdopen(fd, szMode);
    int iRubyModeFlags = parseRubyIoModeFlags(szMode);
    VALUE pRubyIOObject = allocateRubyIoObject();
    OpenFile* pRubyOpenFile = NULL;

    MakeOpenFile(pRubyIOObject, pRubyOpenFile);
    pRubyOpenFile->finalize = ::right_popen_pipe_finalize;
    pRubyOpenFile->mode = iRubyModeFlags;
    pRubyOpenFile->pid = pid;

    if (iRubyModeFlags & FMODE_READABLE)
    {
        pRubyOpenFile->f = pFile;
    }
    if (iRubyModeFlags & FMODE_WRITABLE)
    {
        if (pRubyOpenFile->f)
        {
            pRubyOpenFile->f2 = pFile;
        }
        else
        {
            pRubyOpenFile->f = pFile;
        }
        pRubyOpenFile->mode |= FMODE_SYNC;
    }

    return pRubyIOObject;
}

// Summary:
//  creates a child process using the given command string and creates pipes for
//  use by the child's standard I/O methods. the pipes can be read either
//  synchronously or asynchronously, the latter being recommended for child
//  processes which potentially produce a large amount of output. reading
//  asynchronously also prevents a deadlock condition where the child is blocked
//  writing to a full pipe cache because the other pipe has not been flushed and
//  therefore cannot be read by the calling process, which is blocked reading.
//
// Parameters:
//   variable arguments, as follows:
//      szCommand
//          command to execute including any command-line arguments (required).
//
//      iMode
//          standard I/O file mode (e.g. _O_TEXT or _O_BINARY)
//
//      bShowWindow
//          false to hide child process, true to show
//
//      bAsynchronousOutput
//          false to read synchronously, true to read asynchronously. see
//          also RightPopen::async_read() (defaults to Qfalse).
//
// Returns:
//  a Ruby array containing [stdin write, stdout read, stderr read, pid]
//
// Throws:
//  raises a Ruby RuntimeError on failure
VALUE RightPopen::popen4(const char* szCommand, int iMode, bool bShowWindow, bool bAsynchronousOutput)
{
    VALUE vReturnArray = Qnil;
    PopenData* pPopenData = new PopenData;

    if (false == pPopenData->getChildStdinPair().createPipe(TRUE, FALSE, FALSE) || 
        false == pPopenData->getChildStdoutPair().createPipe(FALSE, TRUE, bAsynchronousOutput) ||
        false == pPopenData->getChildStderrPair().createPipe(FALSE, TRUE, bAsynchronousOutput))
    {
        DWORD dwLastError = ::GetLastError();
        delete pPopenData;
        ::rb_raise(rb_eRuntimeError, "Failed to create pipe: %s", getErrorDescription(dwLastError));
    }
    if (false == pPopenData->createProcess(szCommand, Qfalse != bShowWindow))
    {
        DWORD dwLastError = ::GetLastError();
        delete pPopenData;
        ::rb_raise(rb_eRuntimeError, "Failed to create process: %s", getErrorDescription(dwLastError));
    }

    // wrap piped I/O handles as ruby I/O objects in an array for return.
    DWORD pid = pPopenData->getProcessId();
    {
        VALUE vStdinWrite = createRubyIoObject(pid, iMode, pPopenData->getChildStdinPair().getWrite(), false);
        VALUE vStdoutRead = (Qnil == vStdinWrite) ?
                            Qnil :
                            createRubyIoObject(pid, iMode, pPopenData->getChildStdoutPair().getRead(), true);
        VALUE vStderrRead = (Qnil == vStdoutRead) ?
                            Qnil :
                            createRubyIoObject(pid, iMode, pPopenData->getChildStderrPair().getRead(), true);

        if (Qnil == vStderrRead)
        {
            // avoid double-closing attached handles on destructor call.
            if (Qnil != vStdinWrite)
            {
                pPopenData->getChildStdinPair().forgetWrite();
            }
            if (Qnil != vStdoutRead)
            {
                pPopenData->getChildStdoutPair().forgetRead();
            }

            // fail.
            DWORD dwLastError = ::GetLastError();
            delete pPopenData;
            ::rb_raise(rb_eRuntimeError, "Failed to create ruby I/O object: %s", getErrorDescription(dwLastError));
        }
        pPopenData->attachRubyIOObjects(vStdinWrite, vStdoutRead, vStderrRead);
    }

    // allocate asynchronous I/O buffers, etc., if necessary.
    if (bAsynchronousOutput)
    {
        pPopenData->createAsyncIOData();
    }

    // create Ruby array for returning popen values.
    {
        const long arraySize = 4;

        vReturnArray = rb_ary_new2(arraySize);
        rb_ary_push(vReturnArray, pPopenData->getStdinWriteIOObject());
        rb_ary_push(vReturnArray, pPopenData->getStdoutReadIOObject());
        rb_ary_push(vReturnArray, pPopenData->getStderrReadIOObject());
        rb_ary_push(vReturnArray, UINT2NUM(pid));
    }

    // child is launched. close the parents copy of those pipe handles that only
    // the child should have open. you need to make sure that no handles to the
    // write end of the output pipe are maintained in this process or else the
    // pipe will not close when the child process exits and ReadFile() will hang.
    ::CloseHandle(pPopenData->getChildStdinPair().forgetRead());
    ::CloseHandle(pPopenData->getChildStdoutPair().forgetWrite());
    ::CloseHandle(pPopenData->getChildStderrPair().forgetWrite());

    return vReturnArray;
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
//
// Throws:
//   raises a Ruby RuntimeError on failure
VALUE RightPopen::asyncRead(VALUE vRubyIoObject)
{
    // attempt to find corresponding asynchronous I/O data.
    PopenData* pPopenData = PopenData::findByRubyIOObject(vRubyIoObject);

    if (NULL == pPopenData)
    {
        rb_raise(rb_eRuntimeError, "RightPopen::async_read() parameter refers to an I/O object which was not created by this class.");
    }

    // read.
    return pPopenData->asyncRead(vRubyIoObject);
}
