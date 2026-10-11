# Windows half of lib/platform.sh: reads and writes a secret in Windows
# Credential Manager (a "generic" credential, visible and removable under
# Control Panel > Credential Manager > Windows Credentials), and keeps the
# machine awake while a deploy runs.
#
# Windows has no built-in command that hands a stored secret back, so this
# calls Windows' own credential functions (advapi32) directly. Nothing to
# install. A secret is only ever read from a hidden prompt or written to
# standard output for the calling script; it never appears on a command line.
param(
    [Parameter(Mandatory = $true)][ValidateSet('Read', 'Write', 'KeepAwake')][string]$Action,
    [string]$Target,
    [string]$Marker
)
$ErrorActionPreference = 'Stop'

Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class FoodbankCredential {
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    struct CREDENTIAL {
        public int Flags; public int Type; public string TargetName; public string Comment;
        public System.Runtime.InteropServices.ComTypes.FILETIME LastWritten;
        public int CredentialBlobSize; public IntPtr CredentialBlob; public int Persist;
        public int AttributeCount; public IntPtr Attributes; public string TargetAlias; public string UserName;
    }
    [DllImport("advapi32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    static extern bool CredRead(string target, int type, int flags, out IntPtr credential);
    [DllImport("advapi32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    static extern bool CredWrite(ref CREDENTIAL credential, int flags);
    [DllImport("advapi32.dll")]
    static extern void CredFree(IntPtr credential);
    [DllImport("kernel32.dll")]
    public static extern uint SetThreadExecutionState(uint flags);

    const int CRED_TYPE_GENERIC = 1;
    const int CRED_PERSIST_LOCAL_MACHINE = 2;

    public static string Read(string target) {
        IntPtr p;
        if (!CredRead(target, CRED_TYPE_GENERIC, 0, out p)) return null;
        try {
            CREDENTIAL c = (CREDENTIAL)Marshal.PtrToStructure(p, typeof(CREDENTIAL));
            return Marshal.PtrToStringUni(c.CredentialBlob, c.CredentialBlobSize / 2);
        } finally { CredFree(p); }
    }

    public static bool Write(string target, string secret) {
        byte[] blob = System.Text.Encoding.Unicode.GetBytes(secret);
        CREDENTIAL c = new CREDENTIAL();
        c.Type = CRED_TYPE_GENERIC;
        c.TargetName = target;
        c.UserName = "foodbank";
        c.Persist = CRED_PERSIST_LOCAL_MACHINE;
        c.CredentialBlobSize = blob.Length;
        c.CredentialBlob = Marshal.AllocHGlobal(blob.Length);
        try {
            Marshal.Copy(blob, 0, c.CredentialBlob, blob.Length);
            return CredWrite(ref c, 0);
        } finally { Marshal.FreeHGlobal(c.CredentialBlob); }
    }
}
'@

switch ($Action) {
    'Read' {
        $secret = [FoodbankCredential]::Read($Target)
        if ($null -eq $secret) { exit 1 }
        [Console]::Out.Write($secret)
    }
    'Write' {
        $secure = Read-Host -AsSecureString "Value for $Target (not shown)"
        $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
        try { $plain = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr) }
        finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
        if ([string]::IsNullOrEmpty($plain)) { Write-Error 'nothing entered; nothing stored'; exit 1 }
        if (-not [FoodbankCredential]::Write($Target, $plain)) { exit 1 }
    }
    'KeepAwake' {
        # ES_CONTINUOUS | ES_SYSTEM_REQUIRED: no sleep while the marker exists,
        # which the deploy removes when it finishes, however it finishes.
        [void][FoodbankCredential]::SetThreadExecutionState([uint32]'0x80000001')
        while (Test-Path -LiteralPath $Marker) { Start-Sleep -Seconds 30 }
    }
}
