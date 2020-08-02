[string]$ProcessHelperClassDefinition = @'
namespace ProcessRunner
{
    using System;
    using System.Collections.Generic;
    using System.IO;
    using System.Diagnostics;
    using System.Linq;
    using System.Text;

    /// <summary>
    /// Utility to orchestrate executing applications
    /// </summary>
    public static class ProcessHelper
    {
        /// <summary>
        /// Runs an application with arguments in three distinct modes.
        /// - Utility mode that runs the application synchronously, captures output/error streams and returns them as strings
        /// - Interactive mode for applications like cmd.exe, powershell/pwsh. Doesn't attempt to capture output/error streams.
        /// - Background mode running UI applications - returns without waiting for application termination. Doesn't attempt to capture output/error streams
        /// </summary>
        /// <param name="filePath"></param>
        /// <param name="arguments"></param>
        /// <param name="verb"></param>
        /// <param name="detachUiProcess"></param>
        /// <param name="interactive"></param>
        /// <returns></returns>
        public static ProcessResult Run(FileInfo filePath, List<string> arguments, string verb, bool detachUiProcess, bool interactive)
        {
            if (filePath == null)
            {
                throw new ArgumentNullException(nameof(filePath));
            }

            if (!filePath.Exists)
            {
                throw new FileNotFoundException(string.Empty, filePath.FullName);
            }

            ProcessStartInfo psi = new ProcessStartInfo(filePath.FullName)
            {
                Arguments = string.Join(" ", arguments ?? Enumerable.Empty<string>()),
                UseShellExecute = false,
                Verb = verb,
                RedirectStandardOutput = !interactive,
                RedirectStandardError = !interactive,
            };

            Process process = new Process()
            {
                StartInfo = psi
            };

            StringBuilder output = new StringBuilder();
            StringBuilder error = new StringBuilder();

            process.OutputDataReceived += delegate (object o, DataReceivedEventArgs e)
            {
                output.AppendLine(e.Data);
            };

            process.Start();
            if (!interactive)
            {
                process.BeginOutputReadLine();
            }


            if (detachUiProcess)
            {
                do
                {
                    process.WaitForExit(UiWaitTimeMilliSeconds);
                    process.Refresh();
                    if (!process.HasExited && process.MainWindowHandle != IntPtr.Zero)
                    {
                        // break out of the wait-loop as soon as an HWND is detected
                        break;
                    }
                } while (!process.HasExited);
            }
            else
            {
                process.WaitForExit();
            }

            if (!interactive)
            {
                process.CancelOutputRead();
            }

            if (!interactive && process.HasExited && process.ExitCode != 0)
            {
                error.Append(process.StandardError.ReadToEnd());
            }

            if (process.HasExited)
            {
                return new ProcessResult(filePath.FullName, arguments?.ToArray(), output.ToString(), error.ToString(), process.ExitCode);
            }
            else
            {
                return new RunningProcessResult(filePath.FullName, arguments?.ToArray(), process);
            }
        }

        /// <summary>
        /// Runs an application with arguments in 'Utility' mode
        /// - Utility mode runs the application synchronously, captures output/error streams and returns them as strings
        /// </summary>
        /// <param name="filePath"></param>
        /// <param name="arguments"></param>
        /// <param name="verb"></param>
        /// <returns></returns>
        public static ProcessResult Run(FileInfo filePath, List<string> arguments, string verb)
        {
            return ProcessHelper.Run(filePath, arguments, verb, detachUiProcess: false, interactive: false);
        }

        /// <summary>
        /// Runs an application with arguments in 'Utility' mode
        /// - Utility mode runs the application synchronously, captures output/error streams and returns them as strings
        /// </summary>
        /// <param name="filePath"></param>
        /// <param name="arguments"></param>
        /// <returns></returns>
        public static ProcessResult Run(FileInfo filePath, List<string> arguments)
        {
            return ProcessHelper.Run(filePath, arguments, null);
        }

        /// <summary>
        /// Represents the result of process execution
        /// </summary>
        public class ProcessResult
        {
            /// <summary>
            /// Path to the executable
            /// </summary>
            public readonly string FilePath;

            /// <summary>
            /// Arguments to the application
            /// </summary>
            public readonly string[] Arguments;

            /// <summary>
            /// Output of the application
            /// </summary>
            public readonly string Output;

            /// <summary>
            /// Error generated by the application in the error-stream
            /// </summary>
            public readonly string Error;

            /// <summary>
            /// Exit-code of the process
            /// </summary>
            public readonly int? ExitCode;

            /// <summary>
            /// Creates a <see cref="ProcessResult"/> object
            /// </summary>
            /// <param name="filePath"></param>
            /// <param name="arguments"></param>
            /// <param name="output"></param>
            /// <param name="error"></param>
            /// <param name="exitCode"></param>
            public ProcessResult(string filePath, string[] arguments, string output, string error, int exitCode) : this(filePath, arguments, output, error)
            {
                this.ExitCode = exitCode;
            }

            /// <summary>
            /// Creates a ProcessResult object
            /// </summary>
            /// <param name="filePath"></param>
            /// <param name="arguments"></param>
            /// <param name="output"></param>
            /// <param name="error"></param>
            protected ProcessResult(string filePath, string[] arguments, string output, string error)
            {
                this.FilePath = filePath;
                this.Arguments = arguments;
                this.Output = output;
                this.Error = error;
                this.ExitCode = null;
            }
        }

        /// <summary>
        /// Represents the result of executing a process in the background
        /// </summary>
        public class RunningProcessResult : ProcessResult
        {
            /// <summary>
            /// <see cref="Process"/> object representing a running process.
            /// </summary>
            public readonly Process Process;

            /// <summary>
            /// Creates a <see cref="RunningProcessResult"/> instances
            /// </summary>
            /// <param name="filePath"></param>
            /// <param name="arguments"></param>
            /// <param name="process"></param>
            public RunningProcessResult(string filePath, string[] arguments, Process process) : base(filePath, arguments, string.Empty, string.Empty)
            {
                this.Process = process;
            }
        }

        private const int UiWaitTimeMilliSeconds = 250;
    }
}
'@

Add-Type -TypeDefinition $ProcessHelperClassDefinition