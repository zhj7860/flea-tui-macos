# Stands in for Hyprland's two sockets: workspace>>2 on the ws file (acked by ws-sent), configreloaded on the go file.
import os, socket, sys, threading, time

root, go = sys.argv[1], sys.argv[2]
# How often the stand-in looks for the test's cue files.
poll_s = 0.05
ws = os.path.join(os.path.dirname(go), "ws")
ws_sent = ws + "-sent"


def listen(name):
    path = os.path.join(root, name)
    server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    server.bind(path)
    server.listen(4)
    return server


def commands(server):
    # The request socket answers every command with an empty body, which is all Quickshell's startup queries need.
    while True:
        conn, _ = server.accept()
        conn.recv(4096)
        conn.sendall(b"[]")
        conn.close()


def events(server):
    conn, _ = server.accept()
    while not os.path.exists(ws):
        time.sleep(poll_s)
    conn.sendall(b"workspace>>2\n")
    with open(ws_sent, "w") as marker:
        marker.write("sent\n")
    while not os.path.exists(go):
        time.sleep(poll_s)
    conn.sendall(b"configreloaded>>\n")
    time.sleep(60)


threading.Thread(target=commands, args=(listen(".socket.sock"),), daemon=True).start()
events(listen(".socket2.sock"))
