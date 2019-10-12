#include <stdio.h>
#include <stdlib.h>
#include <sys/socket.h>
#include <arpa/inet.h>
#include <sys/types.h>
#include <string.h>
#include <unistd.h>
#include <netdb.h>
#define tellosocket_buff_len 8192

//return socket fd
int tellosocket_server(const char *address, int port) {
  
    //create socket
    int socketfd=0, err = -1;
    socketfd = socket(AF_INET, SOCK_DGRAM, 0);
    if (socketfd == -1) {
        return -1;
    }
  
    //socket connect
    struct sockaddr_in info;
    bzero(&info, sizeof(info));
    info.sin_family = PF_INET;
    info.sin_addr.s_addr = inet_addr(address);
    info.sin_port = htons(port);
  
    err = connect(socketfd, (struct sockaddr *)&info, sizeof(info));
    if (err != -1) {
        return socketfd;
    }
    else {
        return -1;
    }
}

int tellosocket_recive(int socketfd, char *outdata, int expted_len) {
    
    int len = (int)recv(socketfd, outdata, expted_len, 0);
    return len;
    
}

int tellosocket_close(int socketfd) {
    return close(socketfd);
}

//return socket fd
int tellosocket_client() {
    //create socket
    int socketfd = 0;
    socketfd = socket(AF_INET, SOCK_DGRAM, 0);
    if (socketfd == -1) {
        return -1;
    }
  
    return socketfd;
}

int tellosocket_get_server_ip(char *host, char *ip) {
    struct hostent *hp;
    struct sockaddr_in address;
  
    hp = gethostbyname(host);
    if (hp == NULL) {
        return -1;
    }
  
    bcopy((char *)hp->h_addr, (char *)&address.sin_addr, hp->h_length);
    char *clientip = inet_ntoa(address.sin_addr);
    memcpy(ip, clientip, strlen(clientip));
  
    return 0;
}

//send message to address and port
int tellosocket_send(int socket_fd, char *msg, int len) {
    
    int sendlen = (int)send(socket_fd, msg, len, 0);
    return sendlen;
    
}
