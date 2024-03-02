import socket
import time

infile = input("Enter file name:")
while True:
    file = open(infile, "rt")

    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)

    while True:
        input = file.readline()
        if len(input) == 0:
            break;
        data = bytes(input, 'UTF-8')
        sock.sendto(data, ("127.0.0.1", 49002))
        time.sleep(0.01)

    file.close()
    sock.close()
