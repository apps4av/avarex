import socket
import time

infile = input("Enter file name:")
file = open(infile, "rb")

socket = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)

while True:
    data = file.read(256)
    socket.sendto(data, ("127.0.0.1", 43211))
    if len(data) == 0:
        break;
    time.sleep(0.01)

file.close()
socket.close()
