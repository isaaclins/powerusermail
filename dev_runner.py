import os
import time
import subprocess
import sys
import signal

# Configuration
PROJECT_SCHEME = "PowerUserMail"
# Path to the binary inside the .app bundle
APP_PATH = "build/Build/Products/Debug/PowerUserMail.app/Contents/MacOS/PowerUserMail"
SOURCE_DIR = "PowerUserMail"

current_process = None

def build():
    print("🔨 Building (verbose)...")
    result = subprocess.run(
        [
            "xcodebuild",
            "-project", "PowerUserMail.xcodeproj",
            "-scheme", PROJECT_SCHEME,
            "-configuration", "Debug",
            "-destination", "generic/platform=macOS",
            "-derivedDataPath", "build",
        ],
        capture_output=True,
        text=True
    )
    if result.returncode != 0:
        print("❌ Build failed:")
        if result.stderr:
            print(result.stderr)
        if result.stdout:
            print(result.stdout)
        return False
    print("✅ Build succeeded.")
    return True

def run_app():
    global current_process
    if current_process:
        print("🛑 Stopping previous instance...")
        # Try to terminate gracefully
        current_process.terminate()
        try:
            current_process.wait(timeout=1)
        except subprocess.TimeoutExpired:
            print("Force killing...")
            current_process.kill()
    
    # Ensure any lingering instances are killed (e.g. from previous runs or crashes)
    # We use -9 to force kill and ensure it's really gone
    subprocess.run(["killall", "-9", "PowerUserMail"], capture_output=True)
    time.sleep(0.5) # Give the OS a moment to clean up
    
    print("🚀 Running app (logs will appear below)...")
    print("-" * 40)
    # Run directly to capture stdout/stderr in the current terminal
    if os.path.exists(APP_PATH):
        # We don't capture output here, we let it flow to the terminal
        current_process = subprocess.Popen([APP_PATH])
    else:
        print(f"❌ App binary not found at {APP_PATH}")

def get_max_mtime():
    max_mtime = 0
    for root, dirs, files in os.walk(SOURCE_DIR):
        for f in files:
            if f.endswith(".swift") or f.endswith(".entitlements") or f.endswith(".plist"):
                path = os.path.join(root, f)
                try:
                    mtime = os.path.getmtime(path)
                    if mtime > max_mtime:
                        max_mtime = mtime
                except:
                    pass
    return max_mtime

def main():
    print(f"👀 Watching for changes in {SOURCE_DIR}...")
    last_mtime = get_max_mtime()
    
    # Initial build and run
    if build():
        run_app()
    
    try:
        while True:
            time.sleep(1)
            current_mtime = get_max_mtime()
            if current_mtime > last_mtime:
                print("\n🔄 Change detected. Rebuilding...")
                # Update last_mtime immediately to avoid double triggers
                last_mtime = current_mtime
                # Add a small buffer to let file writes finish
                time.sleep(0.5)
                if build():
                    run_app()
    except KeyboardInterrupt:
        print("\n👋 Exiting...")
        if current_process:
            current_process.terminate()
        sys.exit(0)

if __name__ == "__main__":
    main()
