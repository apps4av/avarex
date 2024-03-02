import socket
import time

infile = input("Enter file name:")
while True:
    file = open(infile, "rb")

    socket = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)

    while True:
        data = file.read(256)
        if len(data) == 0:
            break;
        socket.sendto(data, ("127.0.0.1", 43211))
        time.sleep(0.01)

    file.close()
    socket.close()
