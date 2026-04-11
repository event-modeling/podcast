# KDE Widget for add-seconds.fish

this is a project to create a widget for kde plasma that will run the script add-seconds.fish with a pop up for the seconds offset

## How to use

1. Copy the widget to your widgets folder
2. Restart plasma
3. Add the widget to your desktop
4. Configure the widget to use the add-seconds.fish script
5. Use the widget

## How it works

The KDE Plasma widget is a QML component (`main.qml`) that connects to the `add-seconds.fish` shell script via Plasma's `PlasmaCore.DataSource` and its `executable` engine. This engine exposes child process standard file descriptors (stdin, stdout, stderr) and execution exit statuses back to the QML UI asynchronously. 

### Key Technical Limitations & Solutions

1. **QProcess Pipe Hanging (The "Running..." Forever Bug)**
   When the script modifies the system clipboard, it invokes command line utilities like `wl-copy` (Wayland) or `xclip` (X11). These utilities inherently fork heavily into the background in order to hold onto clipboard memory after execution. By default, these background daemons inherit the Standard Out (STDOUT) and Standard Error (STDERR) open file descriptors from their parent.
   Because `PlasmaCore.DataSource` is powered by Qt's `QProcess`, it explicitly waits until the stdout/stderr data pipes fully close before considering the task "finished" and firing `onNewData`. Consequently, the widget sat forever waiting for an `EOF` that was pinned open by backgrounded daemons.
   **Solution:** We bypassed QProcess pipe inheritance by wrapping the execution securely in a `bash -c` block. Specifically, the widget redirects the script execution output transparently into temporary files (`~/.cache/add_seconds_widget.out` and `.err`), fetches the exit status, and uses `cat` to return the data synchronously. 

2. **QML Execution Scoping & Invisible `ReferenceError`**
   The widget uses KDE's `Plasmoid.fullRepresentation`, which acts as a dynamic inline component. In QML, dynamic item structures have their own contained scope boundaries. The executable `DataSource` connection was anchored at the `root` level file—so when `onNewData` triggered, it silently blew up when trying to directly reference `statusLabel` because it couldn't locate it dynamically.
   **Solution:** "State Lifting." We hoisted the UI visual properties (`property string statusText` and `property color statusColor`) directly up to the `root` object. The `statusLabel` binds itself to the root variables, while the `DataSource` modifies them seamlessly.

3. **Robust Subsystem Logging & Validation**
   - **CLI Layer:** `add-seconds.fish` was modernized with explicit dependency installation checks (`wl-paste`/`xclip`), Wayland/X11 environment logging, and operation metrics to `~/add-seconds.log`.
   - **UI Layer:** `main.qml` was given a secondary `logger` `DataSource` solely for recording user interactions, framework errors, integer validations, and exit codes natively to `~/.cache/add_seconds_widget.log` utilizing `Date().toISOString()` to guarantee timestamp isolation from shell variables.
