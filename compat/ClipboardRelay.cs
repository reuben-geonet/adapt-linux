using System;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Text;
using System.Windows.Forms;

// Materialize ADAPT keyboard copies/cuts. This hook sees only this Wine
// session's input; it neither records typing nor intercepts native Linux input.
// Clipboard text travels only over the parent's private stdout pipe.
internal static class ClipboardRelay
{
    private delegate IntPtr KeyboardProc(int code, IntPtr message, IntPtr data);
    private static readonly KeyboardProc HookProc = OnKeyboard;
    private static IntPtr hook;
    private static bool shortcutDown;
    private static bool pending;
    private static uint before;
    private static DateTime deadline;
    private static readonly bool Trace = Environment.GetEnvironmentVariable("ADAPT_CLIPBOARD_TRACE") == "1";

    [DllImport("user32.dll")]
    private static extern uint GetClipboardSequenceNumber();
    [DllImport("user32.dll")]
    private static extern IntPtr GetClipboardOwner();
    [DllImport("user32.dll")]
    private static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")]
    private static extern uint GetWindowThreadProcessId(IntPtr window, out uint processId);
    [DllImport("user32.dll")]
    private static extern short GetAsyncKeyState(int key);
    [DllImport("user32.dll", SetLastError = true)]
    private static extern IntPtr SetWindowsHookEx(int id, KeyboardProc callback, IntPtr module, uint thread);
    [DllImport("user32.dll")]
    private static extern bool UnhookWindowsHookEx(IntPtr handle);
    [DllImport("user32.dll")]
    private static extern IntPtr CallNextHookEx(IntPtr handle, int code, IntPtr message, IntPtr data);
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode)]
    private static extern IntPtr GetModuleHandle(string name);

    private static bool OwnedByAdapt(IntPtr window)
    {
        uint processId;
        if (window == IntPtr.Zero || GetWindowThreadProcessId(window, out processId) == 0)
            return false;
        try
        {
            using (var process = Process.GetProcessById((int)processId))
                return process.ProcessName.Equals("Adapt.Presentation.WPF",
                    StringComparison.OrdinalIgnoreCase);
        }
        catch (ArgumentException) { return false; }
        catch (InvalidOperationException) { return false; }
    }

    private static IntPtr OnKeyboard(int code, IntPtr message, IntPtr data)
    {
        if (code >= 0)
        {
            int key = Marshal.ReadInt32(data);
            if (key == 0x43 || key == 0x58) // C or X; never collect other keys.
            {
                int kind = message.ToInt32();
                if ((kind == 0x100 || kind == 0x104) &&
                    (GetAsyncKeyState(0x11) & 0x8000) != 0 &&
                    OwnedByAdapt(GetForegroundWindow()))
                {
                    before = GetClipboardSequenceNumber();
                    shortcutDown = true;
                    pending = false;
                }
                else if ((kind == 0x101 || kind == 0x105) && shortcutDown)
                {
                    shortcutDown = false;
                    pending = true;
                    deadline = DateTime.UtcNow.AddMilliseconds(500);
                }
            }
        }
        return CallNextHookEx(hook, code, message, data);
    }

    [STAThread]
    private static void Main()
    {
        hook = SetWindowsHookEx(13, HookProc, GetModuleHandle(null), 0); // WH_KEYBOARD_LL
        if (hook == IntPtr.Zero)
            throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());
        var timer = new System.Windows.Forms.Timer { Interval = 20 };
        timer.Tick += delegate
        {
            if (!pending) return;
            if (DateTime.UtcNow > deadline)
            {
                if (Trace) Console.Error.WriteLine("expired before={0} now={1} source={2}", before,
                    GetClipboardSequenceNumber(), OwnedByAdapt(GetClipboardOwner()));
                pending = false;
                return;
            }
            if (GetClipboardSequenceNumber() == before || !OwnedByAdapt(GetClipboardOwner()))
                return;
            try
            {
                if (!Clipboard.ContainsText(TextDataFormat.UnicodeText)) return;
                string text = Clipboard.GetText(TextDataFormat.UnicodeText);
                if (!OwnedByAdapt(GetClipboardOwner())) { pending = false; return; }
                pending = false;
                if (Trace) Console.Error.WriteLine("export sequence={0}", GetClipboardSequenceNumber());
                // Repeated identical copies and cuts are distinct operations.
                Console.WriteLine(Convert.ToBase64String(Encoding.UTF8.GetBytes(text)));
                Console.Out.Flush();
            }
            catch (ExternalException)
            {
                // A clipboard lock or delayed-rendered value: retry briefly.
            }
        };
        try
        {
            timer.Start();
            Application.Run();
        }
        finally
        {
            timer.Dispose();
            UnhookWindowsHookEx(hook);
        }
    }
}
