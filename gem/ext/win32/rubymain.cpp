#include "RightPopen.h"

// Summary:
//  closes the Ruby I/O objects in the given array.
//
// Parameters:
//   vRubyIoObjectArray
//      array containing three I/O objects to be closed.
//
// Returns:
//  Qnil
extern "C" static VALUE right_popen_close_io_array(VALUE vRubyIoObjectArray)
{
    const int iRubyIoObjectCount = 3;

    for (int i = 0; i < iRubyIoObjectCount; ++i)
    {
        VALUE vRubyIoObject = RARRAY(vRubyIoObjectArray)->ptr[i];

        if (::rb_funcall(vRubyIoObject, rb_intern("closed?"), 0) == Qfalse)
        {
            ::rb_funcall(vRubyIoObject, rb_intern("close"), 0);
        }
    }

    return Qnil;
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
//      vCommand
//          command to execute including any command-line arguments (required).
//
//      vMode
//          text ("t") or binary ("b") mode (defaults to "t").
//
//      vShowWindowFlag
//          Qfalse to hide child process, Qtrue to show (defaults to Qfalse)
//
//      vAsynchronousOutputFlag
//          Qfalse to read synchronously, Qtrue to read asynchronously. see
//          also RightPopen::async_read() (defaults to Qfalse).
//
// Returns:
//  a Ruby array containing [stdin write, stdout read, stderr read, pid]
//
// Throws:
//  raises a Ruby exception on failure
extern "C" static VALUE right_popen_popen4(int argc, VALUE *argv, VALUE klass)
{
    // parse variable arguments.
    VALUE vCommand = Qnil;
    VALUE vMode = Qnil;
    VALUE vShowWindowFlag = Qfalse;
    VALUE vAsynchronousOutputFlag = Qfalse;
    int iMode = 0;
    char* szMode = "t";

    ::rb_scan_args(argc, argv, "13", &vCommand, &vMode, &vShowWindowFlag, &vAsynchronousOutputFlag);
    if (false == NIL_P(vMode))
    {
        szMode = ::StringValuePtr(vMode);
    }
    switch (*szMode)
    {
    case 't':
        iMode = _O_TEXT;
        break;
    case 'b':
        iMode = _O_BINARY;
        break;
    default:
        rb_raise(rb_eArgError, "RightPopen::popen4() argument #2 must be 't' or 'b'");
    }

    RightPopen& rightPopen = RightPopen::getInstance();

    VALUE vReturnArray = rightPopen.popen4(StringValuePtr(vCommand),
                                           iMode,
                                           Qfalse != vShowWindowFlag,
                                           Qfalse != vAsynchronousOutputFlag);

    // ensure handles are closed in block form.
    if (rb_block_given_p())
    {
        return rb_ensure((VALUE(*)(ANYARGS))::rb_yield_splat,
                         vReturnArray,
                         (VALUE(*)(ANYARGS))::right_popen_close_io_array,
                         vReturnArray);
    }

    return vReturnArray;
}

// Summary:
//  reads asynchronously from a pipe opened for overlapped I/O.
//
// Parameters:
//   vSelf
//      should be Qnil since this is a module method.
//
//   vRubyIoObject
//      Ruby I/O object created by previous call to one of this module's popen
//      methods. I/O object should be opened for asynchronous reading or else
//      the behavior of this method is undefined.
//
// Returns:
//  Ruby string object representing a completed asynchronous read OR
//  the empty string to indicate the read is pending OR
//  Qnil to indicate data is not available and no further attempt to read should be made
extern "C" static VALUE right_popen_async_read(VALUE vSelf, VALUE vRubyIoObject)
{
    // parameter check.
    if (NIL_P(vRubyIoObject))
    {
        rb_raise(rb_eRuntimeError, "RightPopen::async_read() parameter cannot be nil.");
    }

    RightPopen& rightPopen = RightPopen::getInstance();

    return rightPopen.asyncRead(vRubyIoObject);
}

// Summary:
//  'RightPopen' module entry point
extern "C" void Init_right_popen()
{
    VALUE vModule = rb_define_module("RightPopen");

    rb_define_module_function(vModule, "popen4", (VALUE(*)(ANYARGS))right_popen_popen4, -1);
    rb_define_module_function(vModule, "async_read", (VALUE(*)(ANYARGS))right_popen_async_read, 1);
}
