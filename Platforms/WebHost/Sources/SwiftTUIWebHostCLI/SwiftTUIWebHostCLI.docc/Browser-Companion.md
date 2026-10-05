# Browser Companion

Operate the same running terminal app from a browser.

## Launch and discovery

On macOS, Linux, and Windows, an interactive `SwiftTUI` app launched with its default
`App.main()` prints a loopback URL before entering full screen. Open it in a
browser for Canvas presentation and semantic controls. It uses assets packaged
with the executable; Node, Bun, a CDN, and an app-specific web build are unnecessary.
No browser opens automatically. The page's Scene selector reaches every app scene.

From another terminal, `myapp --companion-url` prints the URLs of running instances
of that executable. POSIX discovery sockets containing bearer URLs are owner-only.
Windows uses volatile per-instance records beneath the current user's
`Software\SwiftTUI\Companions` registry key, with a protected current-user-only
ACL installed before writing the URL. Records are removed on normal shutdown;
process ID and creation time reject stale crash records or reused process IDs.
Keep the token private; it grants operation of the running application.
Reopen the same URL after closing a page. App exit invalidates the URL and releases
the listener. `--web` instead runs without a terminal and also retains every scene.

| Choice | Behavior |
| --- | --- |
| `--companion auto` (default) | Start when stdin and stdout are terminals. |
| `--companion off` | Run without a companion. |
| `--companion on` | Request a companion explicitly; terminal initialization still requires a usable TTY. |
| `--companion-port 0` (default) | Let the OS allocate an available port. |
| `--companion-port PORT` | Use that port; startup failure reports a retry/opt-out remedy. |

`SWIFTTUI_COMPANION=auto|on|off` and `SWIFTTUI_COMPANION_PORT` provide environment
defaults. Explicit CLI choices win, including port zero. JSON output never starts
a companion. Redirected terminal launch retains the normal “not a TTY” diagnostic;
use `--web` for browser-only/headless operation. A custom main can use `RuntimeConfiguration.builder().companion(.off)`.
The terminal-only `SwiftTUICLI` product has no server; explicit `on` requires the
combined WebHost launcher. Windows secondary scenes are browser-only; POSIX PTY
attachment remains available on macOS/Linux.

## SSH

Run the app on the remote machine with `--companion-port 9134`. In another local
terminal, forward that same port with `ssh -N -L 9134:127.0.0.1:9134 user@host`.
Open the printed tokenized `http://127.0.0.1:9134/` URL in the local browser.
The app and terminal remain on the remote machine. If the local port is occupied,
choose another port for both the app and forwarding. The server stays bound to
127.0.0.1; `--bind` configures browser-only `--web`, not the companion.

## Shared state, input, and layout

Each scene has one run loop, graph, state, and keyboard focus. Browser attachment
adds presentation and input; it never creates a second app. Dormant secondary
scenes retain their state, including while their POSIX PTY is detached. Browser departure
does not end the app. Primary-terminal EOF or app exit stops both hosts.

When both presentations are attached, the common grid is the smaller width and
height of their viewports. Browser enlargement can shrink/reflow it. Terminal
resize or browser geometry changes cancel a pending pointer gesture and reject
input carrying obsolete viewport metadata. Changing input source also cancels
an unfinished pointer gesture, preventing one host from releasing another's press.
Keyboard and assistive actions run serially against the shared state. Assistive
review focus remains independent of keyboard focus.

While attached, the browser supplies presentation preferences; explicit session
options take precedence. Departure restores terminal dimensions and preferences.
Browser copy targets the browser clipboard. Browser paste arrives from that page;
it cannot read the server's OS clipboard. A retired connection cannot mutate
state or acknowledge a successor page's request IDs. An outdated browser adapter
receives a reload diagnostic rather than operating the shared session.

Browser semantic tests establish routing and state preservation. Actual screen
reader speech, editing, and task completion require qualification on the supported
browser and assistive technology combination.
