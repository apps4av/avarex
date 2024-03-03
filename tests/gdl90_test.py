import socket
import time

infile = input("Enter file name:")
while True:
    file = open(infile, "rb")

    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)

    while True:
        data = file.read(256)
        if len(data) == 0:
            break;
        sock.sendto(data, ("127.0.0.1", 43211))
        time.sleep(0.01)

    file.close()
    sock.close()
