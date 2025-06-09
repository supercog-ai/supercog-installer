import psutil
import os
import sys

def kill_python_processes():
    # Get current process ID to avoid killing our own script
    current_pid = os.getpid()
    
    python_processes = []
    for proc in psutil.process_iter(['pid', 'name', 'cmdline']):
        try:
            cmd = " ".join(proc.info['cmdline']) if proc.info['cmdline'] else ""
            # Check if process is a Python process
            if 'python' in proc.info['name'].lower() or 'next dev' in cmd:
                # Don't kill our own process
                if (
                    proc.info['pid'] != current_pid and 
                    '.vscode' not in cmd and 
                    "/Applications" not in cmd and
                    "kill_procs.py" not in cmd
                ):
                    python_processes.append(proc)
        except (psutil.NoSuchProcess, psutil.AccessDenied, psutil.ZombieProcess):
            continue
    
    if not python_processes:
        print("No Python processes found to terminate.")
        return
    
    # Print processes that will be terminated
    print("\nFound Python (and Node) processes:")
    for proc in python_processes:
        try:
            cmdline = ' '.join(proc.info['cmdline']) if proc.info['cmdline'] else 'N/A'
            print(f"PID: {proc.info['pid']}, Command: {cmdline}")
        except (psutil.NoSuchProcess, psutil.AccessDenied):
            continue
    
    # Ask for confirmation
    response = input("\nDo you want to terminate these processes? (y/n): ")
    if response.lower() != 'y':
        print("Operation cancelled.")
        return
    
    # Terminate processes
    for proc in python_processes:
        try:
            proc.terminate()
            print(f"Terminated process {proc.info['pid']}")
        except (psutil.NoSuchProcess, psutil.AccessDenied):
            print(f"Could not terminate process {proc.info['pid']}")
    
    # Wait for processes to terminate
    gone, alive = psutil.wait_procs(python_processes, timeout=3)
    
    # Force kill any remaining processes
    for proc in alive:
        try:
            proc.kill()
            print(f"Force killed process {proc.info['pid']}")
        except (psutil.NoSuchProcess, psutil.AccessDenied):
            print(f"Could not force kill process {proc.info['pid']}")

if __name__ == "__main__":
    kill_python_processes()