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

    VALUE popen4(const char* szCommand, int mode, bool bShowWindow, bool bAsynchronousOutput);
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
